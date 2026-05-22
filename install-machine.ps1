# install-machine.ps1
#
# One-shot per-machine installer for the vscode-jupyter-pair workflow.
# Idempotent: safe to re-run.
#
# 1. Installs jupytext + watchdog via pip (if missing).
# 2. Copies watch.py to %LOCALAPPDATA%\vscode-jupyter-pair\ so per-project
#    .vscode/tasks.json files can reference a stable location.
# 3. Merges the "jupytext sync" task into VSCode's user-level tasks.json
#    (on-demand sync via Ctrl+Shift+P -> Tasks: Run Task -> "jupytext sync").
# 4. Merges the Ctrl+Alt+J keybinding into VSCode's user-level keybindings.json.
# 5. Installs the Notebook Hot Reload VSCode extension
#    (kdkyum.notebook-hot-reload) so external edits to .ipynb files
#    (by Claude, jupytext sync, the watcher, etc.) appear in the open
#    notebook view without manual revert/reopen.
#
# After this, run setup-project.ps1 inside each project that uses paired
# notebooks (drops a .vscode/tasks.json that auto-starts the watcher).
#
# Reload VSCode windows after install to pick up the changes.

$ErrorActionPreference = "Stop"

$kitDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tasksSource = Join-Path $kitDir "vscode\tasks.json"
$keybindSource = Join-Path $kitDir "vscode\keybindings.snippet.json"
$watcherSource = Join-Path $kitDir "watch.py"

$codeUserDir = Join-Path $env:APPDATA "Code\User"
$tasksTarget = Join-Path $codeUserDir "tasks.json"
$keybindTarget = Join-Path $codeUserDir "keybindings.json"

$watcherDir = Join-Path $env:LOCALAPPDATA "vscode-jupyter-pair"
$watcherTarget = Join-Path $watcherDir "watch.py"

# --- 1. Install jupytext + watchdog -----------------------------------------

$jupytext = Get-Command jupytext -ErrorAction SilentlyContinue
if ($jupytext) {
    Write-Host "[ok] jupytext already installed at $($jupytext.Source)"
} else {
    Write-Host "[..] installing jupytext via pip"
    pip install jupytext
    $jupytext = Get-Command jupytext -ErrorAction SilentlyContinue
    if (-not $jupytext) {
        Write-Warning "jupytext still not on PATH after install. Check your Python/pip."
    } else {
        Write-Host "[ok] jupytext installed at $($jupytext.Source)"
    }
}

# watchdog is needed by watch.py
& python -c "import watchdog" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[ok] watchdog already installed"
} else {
    Write-Host "[..] installing watchdog via pip"
    pip install watchdog
    Write-Host "[ok] watchdog installed"
}

# --- 2. Install watch.py to stable location ---------------------------------

New-Item -ItemType Directory -Force -Path $watcherDir | Out-Null
Copy-Item $watcherSource $watcherTarget -Force
Write-Host "[ok] watch.py installed to $watcherTarget"

# --- 3. Install user-level tasks.json --------------------------------------

if (-not (Test-Path $codeUserDir)) {
    Write-Warning "VSCode user dir not found at $codeUserDir. Is VSCode installed?"
    return
}

$sourceTasks = Get-Content $tasksSource -Raw | ConvertFrom-Json

if (Test-Path $tasksTarget) {
    Write-Host "[..] merging into existing $tasksTarget"
    $existing = Get-Content $tasksTarget -Raw | ConvertFrom-Json
    $existingLabels = @($existing.tasks | ForEach-Object { $_.label })
    $newTasks = @($sourceTasks.tasks | Where-Object { $existingLabels -notcontains $_.label })
    if ($newTasks.Count -eq 0) {
        Write-Host "[ok] tasks already present, no changes"
    } else {
        $existing.tasks = @($existing.tasks) + $newTasks
        $existing | ConvertTo-Json -Depth 10 | Set-Content $tasksTarget -Encoding UTF8
        Write-Host "[ok] added $($newTasks.Count) task(s)"
    }
} else {
    Copy-Item $tasksSource $tasksTarget
    Write-Host "[ok] wrote $tasksTarget"
}

# --- 4. Install user-level keybinding -------------------------------------

$sourceBindings = Get-Content $keybindSource -Raw | ConvertFrom-Json

if (Test-Path $keybindTarget) {
    Write-Host "[..] merging into existing $keybindTarget"
    $raw = Get-Content $keybindTarget -Raw
    # keybindings.json allows // comments; strip them for parsing
    $stripped = ($raw -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    $existing = $stripped | ConvertFrom-Json
    if ($null -eq $existing) { $existing = @() }
    $existingKeys = @($existing | ForEach-Object { "$($_.key)|$($_.command)|$($_.args)" })
    $newBindings = @($sourceBindings | Where-Object {
        $sig = "$($_.key)|$($_.command)|$($_.args)"
        $existingKeys -notcontains $sig
    })
    if ($newBindings.Count -eq 0) {
        Write-Host "[ok] keybinding already present, no changes"
    } else {
        $merged = @($existing) + $newBindings
        $merged | ConvertTo-Json -Depth 10 | Set-Content $keybindTarget -Encoding UTF8
        Write-Host "[ok] added $($newBindings.Count) keybinding(s)"
    }
} else {
    Copy-Item $keybindSource $keybindTarget
    Write-Host "[ok] wrote $keybindTarget"
}

# --- 5. Install Notebook Hot Reload extension -----------------------------

$code = Get-Command code -ErrorAction SilentlyContinue
if (-not $code) {
    Write-Warning "'code' CLI not on PATH. Install the extension manually:"
    Write-Warning "  Open VSCode -> Extensions -> search 'Notebook Hot Reload' (kdkyum.notebook-hot-reload)"
} else {
    $installed = & code --list-extensions 2>$null
    if ($installed -contains "kdkyum.notebook-hot-reload") {
        Write-Host "[ok] kdkyum.notebook-hot-reload already installed"
    } else {
        Write-Host "[..] installing kdkyum.notebook-hot-reload"
        & code --install-extension kdkyum.notebook-hot-reload | Out-Null
        Write-Host "[ok] installed kdkyum.notebook-hot-reload"
    }
}

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  1. Reload any open VSCode windows: Ctrl+Shift+P -> 'Developer: Reload Window'"
Write-Host "  2. In each project that uses paired notebooks, run setup-project.ps1"
Write-Host "     (drops a .vscode/tasks.json that auto-starts the watcher)"
Write-Host "  3. First time pairing a notebook: jupytext --set-formats ipynb,py:percent file.ipynb"
Write-Host "  4. Fallback: Ctrl+Alt+J runs an on-demand sync of every .ipynb in the workspace"
