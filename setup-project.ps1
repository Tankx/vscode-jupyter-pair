# setup-project.ps1
#
# Per-project setup: drops a .vscode/tasks.json that auto-starts the
# jupytext watcher when this folder is opened in VSCode.
#
# Idempotent: safe to re-run, won't duplicate the task if present.
#
# Supports two deployment patterns:
#   (1) Kit copied into the project (e.g. <project>/vscode-jupyter-pair/).
#       The generated tasks.json uses a project-relative path to watch.py.
#       No machine-wide install required beyond `pip install jupytext watchdog`.
#   (2) Kit lives somewhere central (e.g. Dropbox) and watch.py was installed
#       to %LOCALAPPDATA%\vscode-jupyter-pair\ by install-machine.ps1.
#       The generated tasks.json uses that stable path.
#
# Auto-detects which pattern applies based on where this script lives
# relative to the project directory.
#
# Usage:
#   .\setup-project.ps1                  # configure the current folder
#   .\setup-project.ps1 C:\path\to\proj  # configure another folder

param([string]$ProjectDir = (Get-Location).Path)

$ErrorActionPreference = "Stop"

$projectDir = (Resolve-Path $ProjectDir).Path
$kitDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$kitDirResolved = (Resolve-Path $kitDir).Path

# Decide which watch.py path to embed in tasks.json
$kitInsideProject = $kitDirResolved.StartsWith($projectDir, [StringComparison]::OrdinalIgnoreCase)

if ($kitInsideProject) {
    # Pattern 1: relative path so the project stays self-contained
    $relative = $kitDirResolved.Substring($projectDir.Length).TrimStart('\','/') -replace '\\', '/'
    $watcherArg = "`${workspaceFolder}/$relative/watch.py"
    $watcherSource = Join-Path $kitDirResolved "watch.py"
    if (-not (Test-Path $watcherSource)) {
        Write-Warning "watch.py not found at $watcherSource."
        return
    }
    Write-Host "[ok] kit detected inside project; using project-relative watch.py"
} else {
    # Pattern 2: stable LOCALAPPDATA path (requires install-machine.ps1 to have run)
    $watcherPath = Join-Path $env:LOCALAPPDATA "vscode-jupyter-pair\watch.py"
    $watcherArg = ($watcherPath -replace '\\', '/')
    if (-not (Test-Path $watcherPath)) {
        Write-Warning "watch.py not found at $watcherPath."
        Write-Warning "Either copy the kit into the project, or run install-machine.ps1 first."
        return
    }
    Write-Host "[ok] kit lives outside project; pointing tasks.json at $watcherPath"
}

$vscDir = Join-Path $projectDir ".vscode"
$tasksFile = Join-Path $vscDir "tasks.json"
New-Item -ItemType Directory -Force -Path $vscDir | Out-Null

$taskJson = @"
{
    "label": "jupytext auto-sync",
    "detail": "Auto-syncs every .ipynb to its paired .py on save",
    "type": "shell",
    "command": "python",
    "args": [
        "$watcherArg",
        "`${workspaceFolder}"
    ],
    "isBackground": true,
    "runOptions": { "runOn": "folderOpen" },
    "presentation": {
        "reveal": "silent",
        "panel": "dedicated",
        "showReuseMessage": false
    },
    "problemMatcher": []
}
"@

if (Test-Path $tasksFile) {
    Write-Host "[..] merging into existing $tasksFile"
    $existing = Get-Content $tasksFile -Raw | ConvertFrom-Json
    $existingLabels = @($existing.tasks | ForEach-Object { $_.label })
    if ($existingLabels -contains "jupytext auto-sync") {
        Write-Host "[ok] task 'jupytext auto-sync' already present, no changes"
    } else {
        $newTask = $taskJson | ConvertFrom-Json
        $existing.tasks = @($existing.tasks) + $newTask
        $existing | ConvertTo-Json -Depth 10 | Set-Content $tasksFile -Encoding UTF8
        Write-Host "[ok] added 'jupytext auto-sync' to $tasksFile"
    }
} else {
    $full = @"
{
    "version": "2.0.0",
    "tasks": [
$taskJson
    ]
}
"@
    Set-Content -Path $tasksFile -Value $full -Encoding UTF8
    Write-Host "[ok] wrote $tasksFile"
}

# Ensure .gitignore covers paired .ipynb files
$gitignoreFile = Join-Path $projectDir ".gitignore"
$ignoreBlock = @"

# Notebooks paired with .py via jupytext - only .py is committed
*.ipynb
.ipynb_checkpoints/
"@
if (Test-Path $gitignoreFile) {
    $current = Get-Content $gitignoreFile -Raw
    if ($current -notmatch '\*\.ipynb') {
        Add-Content -Path $gitignoreFile -Value $ignoreBlock
        Write-Host "[ok] appended *.ipynb to $gitignoreFile"
    } else {
        Write-Host "[ok] $gitignoreFile already ignores *.ipynb"
    }
} else {
    Set-Content -Path $gitignoreFile -Value $ignoreBlock.TrimStart() -Encoding UTF8
    Write-Host "[ok] created $gitignoreFile"
}

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  1. Reload this VSCode window: Ctrl+Shift+P -> 'Developer: Reload Window'"
Write-Host "  2. When VSCode asks 'Allow automatic tasks in this folder?', click Allow"
Write-Host "  3. Confirm 'jupytext auto-sync' is running (Terminal panel -> dropdown)"
Write-Host "  4. Save an .ipynb -> matching .py updates within ~1 second"
