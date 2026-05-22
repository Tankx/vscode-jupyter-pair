#!/usr/bin/env python3
"""Background watcher: keeps every .ipynb in a directory tree in sync with its
paired .py via jupytext.

Triggered by VSCode (or any editor) saving an .ipynb. Re-pairs on every event
using `--set-formats`, so VSCode's habit of stripping the jupytext metadata
on save is harmless.

Usage:
    python watch.py [DIR]

DIR defaults to the current working directory.
"""

from __future__ import annotations

import functools
import subprocess
import sys
import threading
import time
from pathlib import Path

from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

# Force line-buffered output so logs appear promptly in VSCode terminal,
# not at end-of-process.
print = functools.partial(print, flush=True)  # noqa: A001

DEBOUNCE_SECONDS = 0.4   # collapse rapid duplicate saves
EXCLUDED_DIRS = {".ipynb_checkpoints", ".git", "__pycache__", "node_modules"}


def is_relevant(path: Path) -> bool:
    if path.suffix != ".ipynb":
        return False
    # jupytext creates short-lived "*_tmp_jupytext_*.ipynb" sibling files during
    # its own sync; ignore those or we trigger a self-loop and a FileNotFoundError.
    if "_tmp_jupytext_" in path.name:
        return False
    return not any(part in EXCLUDED_DIRS for part in path.parts)


def sync(path: Path) -> None:
    try:
        result = subprocess.run(
            ["jupytext", "--set-formats", "ipynb,py:percent", "--sync", str(path)],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            print(f"[sync] {path}")
        else:
            print(f"[fail] {path}: {result.stderr.strip().splitlines()[-1] if result.stderr else 'unknown error'}")
    except subprocess.TimeoutExpired:
        print(f"[timeout] {path}")
    except FileNotFoundError:
        print("[fatal] jupytext command not found on PATH. pip install jupytext.")
        raise SystemExit(2)


class Debouncer:
    """Collapse a flurry of events on the same path into one sync."""

    def __init__(self, delay: float):
        self.delay = delay
        self._timers: dict[str, threading.Timer] = {}
        self._lock = threading.Lock()

    def fire(self, path: Path) -> None:
        key = str(path)
        with self._lock:
            old = self._timers.pop(key, None)
            if old is not None:
                old.cancel()
            t = threading.Timer(self.delay, lambda: sync(path))
            t.daemon = True
            self._timers[key] = t
            t.start()


class IpynbHandler(FileSystemEventHandler):
    def __init__(self, debouncer: Debouncer):
        self.debouncer = debouncer

    def on_modified(self, event):
        self._maybe(event)

    def on_created(self, event):
        self._maybe(event)

    def _maybe(self, event):
        if event.is_directory:
            return
        path = Path(event.src_path)
        if is_relevant(path):
            self.debouncer.fire(path)


def main(watch_dir: Path) -> None:
    if not watch_dir.is_dir():
        print(f"[fatal] not a directory: {watch_dir}")
        raise SystemExit(1)

    debouncer = Debouncer(DEBOUNCE_SECONDS)
    handler = IpynbHandler(debouncer)
    observer = Observer()
    observer.schedule(handler, str(watch_dir), recursive=True)
    observer.start()

    print(f"[watch] active on {watch_dir} (re-pair + sync every .ipynb save)")
    try:
        while True:
            time.sleep(60)   # keep main thread alive
    except KeyboardInterrupt:
        print("[watch] stopping")
    finally:
        observer.stop()
        observer.join()


if __name__ == "__main__":
    target = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    main(target)
