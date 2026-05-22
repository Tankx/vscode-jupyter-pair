# vscode-jupyter-pair

A small kit for handling Jupyter notebooks in VSCode without their usual
git-noise drawbacks. You edit `.ipynb` in VSCode normally; a paired `.py`
(jupytext "percent" format) is the canonical, committable artefact. Saves
auto-sync. Claude can sync too.

## What this kit gives you

- **Edit notebooks in VSCode like normal.** Save with Ctrl+S.
- **Every save auto-syncs to the paired `.py`** via a background watcher
  that VSCode starts when the project opens.
- **Git only sees `.py`** — clean line diffs, no JSON noise, no notebook outputs in history.
- **Claude's edits appear in your open notebook view automatically** via the
  Notebook Hot Reload extension — no manual revert/reopen.
- **Claude knows the workflow.** Point Claude at `claude-instructions.md`
  and it will run `jupytext --sync` before reading or editing paired
  files, and warn when a kernel restart is needed.
- **Manual fallback: Ctrl+Alt+J** force-syncs the workspace from anywhere
  (useful if the watcher isn't running).

## What's in the box

| File | Purpose |
|---|---|
| `README.md` | This file. |
| `install-machine.ps1` | One-shot installer for a new Windows machine. Installs jupytext + watchdog (pip), copies `watch.py` to a stable location, writes the VSCode user-level task + keybinding, installs the Notebook Hot Reload extension. Idempotent. |
| `setup-project.ps1` | Per-project setup. Drops a `.vscode/tasks.json` that auto-starts the watcher when the project opens. Adds `*.ipynb` to `.gitignore`. Idempotent. |
| `watch.py` | The background watcher. Watches the project tree for `.ipynb` changes; runs `jupytext --set-formats --sync` on each save with a small debounce. Re-pairing on every event defeats VSCode's metadata stripping. |
| `vscode/tasks.json` | User-level "jupytext sync" task for the manual fallback (Ctrl+Alt+J). The installer copies this into `%APPDATA%\Code\User\tasks.json` (merging if needed). |
| `vscode/keybindings.snippet.json` | The Ctrl+Alt+J binding to merge into `%APPDATA%\Code\User\keybindings.json`. |
| `claude-instructions.md` | Reference file you point Claude at when you want it to follow this workflow on a project. Not auto-loaded. |

## Two deployment patterns

The kit supports both — `setup-project.ps1` detects which one you're using.

### Pattern A: Copy the kit into each project (recommended for portability)

```powershell
# 1. copy this whole folder into the project
cp -r vscode-jupyter-pair c:\path\to\your\project\

# 2. set the project up (uses a relative path to watch.py)
cd c:\path\to\your\project
powershell .\vscode-jupyter-pair\setup-project.ps1
```

Result: the project is self-contained. `.vscode/tasks.json` references
`${workspaceFolder}/vscode-jupyter-pair/watch.py`. No machine-wide install
needed beyond `pip install jupytext watchdog`. Clone the repo on another
PC, install those two pip packages, reload VSCode — auto-sync just works.

You'll likely want to commit the `vscode-jupyter-pair/` folder so
collaborators get it on clone.

### Pattern B: One kit shared across all projects (Dropbox / global)

```powershell
# 1. one-time machine setup: put kit somewhere stable and run the installer
Move-Item .\vscode-jupyter-pair d:\Dropbox\Tools\
cd d:\Dropbox\Tools\vscode-jupyter-pair
.\install-machine.ps1
```

That gives you, machine-wide:
- `jupytext` and `watchdog` on your Python (pip)
- `watch.py` copied to `%LOCALAPPDATA%\vscode-jupyter-pair\`
- VSCode user-level "jupytext sync" task + `Ctrl+Alt+J` keybinding (manual fallback)
- Notebook Hot Reload extension (`kdkyum.notebook-hot-reload`)

```powershell
# 2. for each project that uses paired notebooks
cd c:\path\to\some\project
powershell d:\Dropbox\Tools\vscode-jupyter-pair\setup-project.ps1
```

Result: `.vscode/tasks.json` references `%LOCALAPPDATA%\vscode-jupyter-pair\watch.py`.
The project itself stays clean (no kit files inside it), but every PC
needs `install-machine.ps1` run once first.

### Mac/Linux equivalents (manual)

For pattern B, the user-level task + keybinding go in:
- macOS — `~/Library/Application Support/Code/User/`
- Linux — `~/.config/Code/User/`

Copy `vscode/tasks.json` and merge `vscode/keybindings.snippet.json`.

### First time pairing a notebook
```bash
jupytext --set-formats ipynb,py:percent some_notebook.ipynb
```
This writes the pairing metadata into the file. Once done, the pairing persists.

### Day-to-day
1. Open `some_notebook.ipynb` in VSCode. Edit, save normally (Ctrl+S).
2. The watcher syncs to `some_notebook.py` within ~1 second of each save.
3. Commit only the `.py`. `.gitignore` already excludes `*.ipynb`.
4. Manual fallback: **Ctrl+Alt+J** force-syncs everything in the
   workspace (useful if the watcher isn't running, e.g. you skipped the
   "Allow automatic tasks" prompt).

## Architecture — how the pieces interact

Three places state lives, and the gotchas are all about disconnects between them.

```
┌─────────────────────────┐    ┌─────────────────────────┐    ┌────────────────────┐
│  Disk                   │    │  VSCode notebook UI     │    │  Jupyter kernel    │
│  (file contents)        │ ←→ │  (in-memory model)      │ ←→ │  (Python process,  │
│  - foo.ipynb (JSON)     │    │  - cell text            │    │   variables,       │
│  - foo.py (paired)      │    │  - dirty markers        │    │   imports)         │
│                         │    │  - displayed outputs    │    │                    │
└─────────────────────────┘    └─────────────────────────┘    └────────────────────┘
```

| Layer | Source of truth for... | Updates when... |
|---|---|---|
| Disk | The committable artefact (.py) | Ctrl+S in VSCode, watcher's `jupytext --sync`, Claude edit, Ctrl+Alt+J |
| VSCode UI | What you see in the notebook tab | Ctrl+S writes, Notebook Hot Reload reads, you type |
| Kernel | What `Run Cell` actually executes | You run a cell (does NOT reread disk) |

### Why the disconnects matter

- **Claude writes to disk only.** It cannot push into VSCode's buffer.
  Without the Notebook Hot Reload extension, Claude's notebook edits are
  invisible until you close/reopen the file. **With** the extension, the
  disk → UI step is automatic.
- **The kernel is its own world.** Code changes on disk (whether from
  Claude or from you editing the .py and syncing) **do not** update what's
  bound in the running kernel. A redefined `def plot_year` still resolves
  to the old version until you re-execute that cell. A changed
  `%matplotlib widget` magic still uses the previous backend until kernel
  restart. There is no tool that fixes this — it's how Python execution
  works.
- **Unsaved edits in VSCode are invisible to Claude.** Claude reads from
  disk. If you have dirty buffers, save first (Ctrl+S) before asking
  Claude to edit, or you'll get a merge mess.

### Rules of thumb

- **Source-only changes** (markdown, comments, a new unrun cell): hot
  reload covers it. No restart needed.
- **Code-behavior changes** (function bodies, imports, magics, anything
  that re-binds a name in the kernel): restart kernel → Run All.
- **Before asking Claude to touch a notebook**: save it (Ctrl+S). Claude
  reads from disk and won't see your dirty buffer.
- **After Claude edits a paired file**: the watcher syncs the twin
  automatically. If for any reason the watcher isn't running, press
  Ctrl+Alt+J.

## Use with Claude

`claude-instructions.md` is the file you point Claude at when you want it
to follow this workflow on a project. It is **not** auto-loaded — you
reference it explicitly. Pick whichever fits your setup:

- Point Claude at it directly in chat: *"Read `path/to/vscode-jupyter-pair/claude-instructions.md` and follow it for this project."*
- Or, in your project's existing `CLAUDE.md` (if you have one), add a single line: `Follow the jupytext workflow described in [path/to/vscode-jupyter-pair/claude-instructions.md].`
- Or, paste the contents into a system prompt / project memory once.

The instructions tell Claude to:
- Treat the `.py` as canonical
- Run `jupytext --sync foo.ipynb` before reading the `.py` if the `.ipynb`
  is newer (in case you edited in VSCode but didn't press Ctrl+Alt+J yet)
- Run `jupytext --sync foo.ipynb` after editing the `.py` so the `.ipynb`
  picks up your changes when you next open it in VSCode
- Flag when a kernel restart is needed (function/import changes, magics)
- Refuse to edit a notebook if the user might have unsaved buffer changes

The markdown is the entire spec — no extension or plugin needed on Claude's side.

## How the auto-sync watcher works

The simpler approach — a save-on-change VSCode extension like
`emeraldwalk.runonsave` — doesn't help here, because VSCode's notebook
editor is a `NotebookDocument`, not a `TextDocument`, so those extensions
never see notebook saves.

What the kit ships instead is `watch.py`: a small filesystem watcher
(Python + `watchdog`) that VSCode auto-starts as a background task when
the project opens. It operates at the OS level, so it catches every
`.ipynb` write regardless of who wrote it (VSCode, Claude, JupyterLab,
manual `cp`).

For each change it runs:
```bash
jupytext --set-formats ipynb,py:percent --sync <file>.ipynb
```

The `--set-formats` re-establishes the pairing every time, which
neutralises VSCode's habit of stripping jupytext metadata on save. A
small debounce (0.4s) collapses rapid duplicate save events. Jupytext's
own `*_tmp_jupytext_*.ipynb` scratch files are filtered out so the
watcher doesn't self-trigger.

Trade-off: the watcher process must be running. `setup-project.ps1`
wires it to auto-start on folder open via `.vscode/tasks.json`, which
needs you to click "Allow automatic tasks" once per workspace. If you
ever decline that prompt or kill the task, `Ctrl+Alt+J` is the manual
fallback that re-syncs everything immediately.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Saves aren't auto-syncing | The watcher isn't running. Open the Terminal panel — look for a dedicated terminal called "jupytext auto-sync". If absent: `Ctrl+Shift+P → Tasks: Run Task → jupytext auto-sync`. If you declined VSCode's "Allow automatic tasks" prompt, run `Ctrl+Shift+P → Manage Automatic Tasks → Allow` and reload. |
| Watcher terminal shows `[fatal] jupytext command not found` | The Python the watcher launched doesn't have jupytext. Edit `.vscode/tasks.json` to use a specific `python.exe` (e.g. your Anaconda one) instead of bare `python`. |
| Watcher shows `[fail] ... FileNotFoundError ... _tmp_jupytext_*` | Should already be filtered. If you still see it, update `watch.py` from the kit. |
| Ctrl+Alt+J does nothing | Reload VSCode. The user-level task only loads on window startup. |
| `jupytext: command not found` | Activate the Python where you `pip install`ed it. Or use full path in `tasks.json`. |
| `.py` doesn't update after Ctrl+Alt+J | The notebook may not be paired. Run `jupytext --set-formats ipynb,py:percent file.ipynb` once. |
| Get a "Notebook is not trusted" warning | Benign — open the notebook in Jupyter once and "Trust" it, or ignore. |
| Ctrl+Alt+J conflicts with another binding | Edit `%APPDATA%\Code\User\keybindings.json` and change the `"key"` to whatever you prefer. |
| Claude edited the notebook but my view didn't update | Make sure the Notebook Hot Reload extension is enabled (`kdkyum.notebook-hot-reload`). Without it, close/reopen the file to see disk changes. |
| Hot reload updated the source but the cell still runs the old code | That's the kernel-state distinction. Restart Kernel → Run All for code-behavior changes (functions, imports, magics). |
| Asked Claude to edit and got mid-merge mess | Probably had unsaved buffer changes when Claude wrote to disk. Save first (Ctrl+S) before delegating notebook edits. |

## Updating

Pull/copy a newer version of this kit, then re-run `install-machine.ps1`.
The installer is idempotent — it merges into existing user-level config
rather than overwriting blindly.
