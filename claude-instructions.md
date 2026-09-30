# Jupytext-paired notebooks — workflow for Claude

> Loaded by the `jupyter-pair` skill (from the `claude-setup` repo) whenever a
> task touches a notebook or a paired `.py`, or pointed at by hand. Treat it as
> a referenced behaviour spec.

This project uses **jupytext** to pair every `.ipynb` notebook with a `.py`
in the "percent" format. The `.py` is the **canonical, committed** artefact;
the `.ipynb` is the editing surface (in VSCode/JupyterLab) and is
**gitignored**.

## Hard rules

1. **The `.py` is the source of truth for git.** Never commit `.ipynb`.
2. **A background watcher is probably running.** If `.vscode/tasks.json`
   includes a `jupytext auto-sync` task, the project has a
   filesystem-level watcher that re-syncs `.ipynb` → `.py` within ~1
   second of every save. You can usually rely on the `.py` being current
   when you read it. **But** if the user just said "I changed X" and the
   `.ipynb` is newer than the `.py` by more than a few seconds, the
   watcher may be off — run `jupytext --sync <name>.ipynb` defensively.
3. **After editing a `.py`**, sync the other direction so the `.ipynb`
   will reflect your changes the next time the user opens it in VSCode:
   ```bash
   jupytext --sync <name>.py
   ```
   (The watcher only sees `.ipynb` saves, not `.py` writes, so this is
   on you.)
4. **`jupytext --sync` is idempotent and fast.** When in doubt, just run it.
5. **Flag kernel-state implications when you make code-behavior changes.**
   See the "Kernel state" section below — the user needs to know when a
   restart is required for your changes to take effect.

## Three places state lives — and the disconnects between them

You operate on **disk**. The user's notebook view is in VSCode's
**in-memory model**. Their `Run Cell` button executes inside a Jupyter
**kernel process**. These three layers don't auto-sync in all directions.

| Layer | Truth for... | When does it update from disk? |
|---|---|---|
| Disk | Committable code (.py) | When something writes (you, jupytext, Ctrl+S) |
| VSCode notebook UI | What the user sees | If they have the Notebook Hot Reload extension (`kdkyum.notebook-hot-reload`), automatically. Otherwise only on reopen. |
| Jupyter kernel | What `Run Cell` actually executes | **Never automatically.** Kernel state only updates when the user re-runs a cell. |

### Implications for what you should do

- **You can't see unsaved buffer edits.** If you suspect the user has
  dirty buffers (recently asked about something they're typing), ask
  them to save first before you edit the notebook on disk. A read of
  a paired `.py` while the user has unsaved `.ipynb` changes will give
  you stale content; your edits then risk overwriting their work.

- **Your edits land on disk instantly via `NotebookEdit` / `Write` /
  `Edit`.** If the user has the Notebook Hot Reload extension (this kit
  installs it by default), their open notebook view picks up your
  changes within ~1 second. If they don't, they'll need to close and
  reopen the file — warn them.

- **Hot reload updates source, NOT kernel state.** Even with hot reload,
  the running kernel holds the *previous* version of any name. Your
  rewrite of `def plot_year` is visible to the user in the source but
  the kernel still has the old binding. Until they re-execute that cell,
  every call to `plot_year` runs the stale version.

### When you must warn about kernel restart

Tell the user "you'll need to restart the kernel and re-run cells" when
your change touches:

- **Function or class definitions** that have already been run
- **Module imports** (especially with non-trivial side effects)
- **Magics** (`%matplotlib`, `%load_ext`, `%env`)
- **Module-level state** (constants, configuration dicts, globals)
- **Anything decorated** (`@dataclass`, `@functools.cache`, etc.) where
  the decoration is cached in the kernel

Pure additions of new cells (that the user will run for the first time)
or pure markdown/comment edits do NOT need a kernel restart — hot reload
alone suffices.

## Detecting a paired file

A jupytext-paired `.py` has this YAML block at the top:

```python
# ---
# jupyter:
#   jupytext:
#     formats: ipynb,py:percent
#     ...
# ---
```

If you see that, the file is paired. The matching `.ipynb` lives next to it
with the same basename.

## Establishing a pairing (first time only)

If the user has a bare `.ipynb` and asks you to start tracking it in git
the right way:

```bash
jupytext --set-formats ipynb,py:percent <file>.ipynb
```

That writes the metadata into both files. Then add `*.ipynb` to `.gitignore`
if it isn't already there.

## What stays in the `.ipynb` only

Cell outputs (plots, dataframe HTML, stack traces). The `.py` has only the
inputs. This is intentional — outputs would balloon git diffs and leak
intermediate data. If the user asks "where did Figure 3 go in the diff?",
the answer is "the figure is in the .ipynb output cell, not in git; the
*code* that produced it is in the .py."

## Typical actions

| User asks | You should |
|---|---|
| "Add a new cell that does X" | Edit the `.py` (add a `# %%` block). Then `jupytext --sync foo.py` so the `.ipynb` updates. No kernel restart needed — new cell is unrun. |
| "Read what I just changed in the notebook" | `jupytext --sync foo.ipynb` first, then read `foo.py`. |
| "Change this function" | Edit `.py`, sync, then warn: "the kernel still has the old `<name>` — restart kernel + re-run cells to pick up the change." |
| "Why does the diff show changes I didn't make?" | Likely a `Ctrl+Alt+J` that picked up VSCode's metadata churn. The actual code change is what matters; the YAML header and cell IDs are noise. |
| "Run this notebook" | `python foo.py` works — paired `.py` files are valid scripts. Or convert and execute: `jupytext --to ipynb --execute foo.py`. |
| "Set up jupytext for this project" | `pip install jupytext` once, then `jupytext --set-formats ipynb,py:percent` on each notebook. Update `.gitignore`. |

## Editing conventions

- A jupytext "percent" cell is everything between two `# %%` lines.
  Markdown cells use `# %% [markdown]` and the body is line-prefixed with
  `# `.
- When you add a code cell, add the `# %%` marker — don't drop loose code
  in the middle of an existing cell.
- The YAML header block at the top is jupytext machinery — don't edit it.

## The Ctrl+Alt+J keybinding (manual fallback)

The user has a VSCode user-level task bound to `Ctrl+Alt+J` that runs:
```bash
jupytext --set-formats ipynb,py:percent --sync **/*.ipynb
```
across the workspace. They use it when the watcher isn't running, or as
a paranoid "make sure everything is current" check before a commit. You
should never need to remind them to press it — just run `jupytext --sync`
yourself before reading and after writing.
