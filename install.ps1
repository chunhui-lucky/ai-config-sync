# ============================================================
# ai-config-sync PowerShell installer (Windows native)
#
# Usage:
#   irm https://raw.githubusercontent.com/chunhui-lucky/ai-config-sync/main/install.ps1 | iex
#   .\install.ps1 -Uninstall
#
# Prerequisites: Git, Python 3, Git Bash
# ============================================================

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$RepoUrl = $env:AI_CONFIG_REPO ?? "https://github.com/chunhui-lucky/ai-config-sync"
$InstallDir = Join-Path $env:USERPROFILE ".config\ai-config-sync"
$BinDir = Join-Path $env:USERPROFILE ".local\bin"

function Write-Ok($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "  [X] $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "  [i] $msg" -ForegroundColor Cyan }

function Test-Command($cmd) {
    try { Get-Command $cmd -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Install {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "  ai-config-sync installer (Windows)" -ForegroundColor Blue
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host ""

    # Check prerequisites
    Write-Host "  [Checking prerequisites]" -ForegroundColor Blue

    if (-not (Test-Command "git")) {
        Write-Err "git not found. Install: https://git-scm.com/download/win"
        exit 1
    }
    Write-Ok "git"

    if (-not (Test-Command "python") -and -not (Test-Command "python3")) {
        Write-Err "Python 3 not found. Install: https://www.python.org/downloads/"
        exit 1
    }
    Write-Ok "python3"

    # Check Git Bash
    $gitBash = $null
    $gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($gitExe) {
        $gitDir = Split-Path (Split-Path $gitExe)
        $gitBash = Join-Path $gitDir "bin\bash.exe"
        if (-not (Test-Path $gitBash)) {
            $gitBash = Join-Path $gitDir "usr\bin\bash.exe"
        }
    }
    if ($gitBash -and (Test-Path $gitBash)) {
        Write-Ok "Git Bash ($gitBash)"
    } else {
        Write-Err "Git Bash not found. Reinstall Git for Windows with Git Bash."
        exit 1
    }

    # Install / update
    Write-Host ""
    Write-Host "  [Installing]" -ForegroundColor Blue

    if (Test-Path (Join-Path $InstallDir ".git")) {
        Write-Info "Already installed, updating..."
        Push-Location $InstallDir
        git pull --quiet 2>$null
        Pop-Location
        Write-Ok "Updated: $InstallDir"
    } elseif (Test-Path $InstallDir) {
        Write-Warn "Directory exists but not a git repo, backing up"
        $backup = "$InstallDir.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Rename-Item $InstallDir $backup
        git clone --quiet $RepoUrl $InstallDir
        Write-Ok "Installed: $InstallDir"
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir) | Out-Null
        git clone --quiet $RepoUrl $InstallDir
        Write-Ok "Installed: $InstallDir"
    }

    # Create bin link
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Write-Host ""
    Write-Host "  [Linking]" -ForegroundColor Blue

    # Copy main script
    $linkTarget = Join-Path $BinDir "ai-config"
    Copy-Item (Join-Path $InstallDir "bin\ai-config") $linkTarget -Force
    Write-Ok "ai-config -> $linkTarget"

    # Create .bat wrapper for cmd.exe
    $batTarget = Join-Path $BinDir "ai-config.bat"
    @"
@echo off
"$gitBash" "$linkTarget" %*
"@ | Set-Content $batTarget -Encoding ASCII
    Write-Ok "ai-config.bat -> $batTarget (cmd.exe wrapper)"

    # Create .ps1 wrapper for PowerShell
    $ps1Target = Join-Path $BinDir "ai-config.ps1"
    @"
# ai-config PowerShell wrapper
& '$gitBash' '$linkTarget' @args
"@ | Set-Content $ps1Target -Encoding UTF8
    Write-Ok "ai-config.ps1 -> $ps1Target (PowerShell wrapper)"

    # Add to PATH
    Write-Host ""
    Write-Host "  [PATH]" -ForegroundColor Blue
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$BinDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$BinDir;$userPath", "User")
        Write-Ok "Added $BinDir to user PATH"
        Write-Info "Restart your terminal for PATH changes to take effect"
    } else {
        Write-Ok "$BinDir already in PATH"
    }

    # Install watchdog
    Write-Host ""
    Write-Host "  [Windows extras]" -ForegroundColor Blue
    try {
        python -c "import watchdog" 2>$null
        if ($LASTEXITCODE -ne 0) { throw }
        Write-Ok "watchdog (already installed)"
    } catch {
        Write-Info "Installing watchdog (for file watching)..."
        pip install watchdog 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "watchdog installed"
        } else {
            Write-Warn "watchdog install failed (auto-watch may not work)"
            Write-Info "Try: pip install watchdog"
        }
    }

    Write-Host ""
    Write-Host "  Done!" -ForegroundColor Green
    Write-Host ""
    Write-Info "Get started (in Git Bash):"
    Write-Host ""
    Write-Host "    ai-config init       # Initialize (scan & merge existing configs)"
    Write-Host "    ai-config sync       # Sync configs to all tools"
    Write-Host "    ai-config status     # Check status"
    Write-Host "    ai-config help       # All commands"
    Write-Host ""
}

function Uninstall {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "  ai-config-sync uninstaller" -ForegroundColor Blue
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host ""

    # Stop watcher task
    try {
        Unregister-ScheduledTask -TaskName "AIConfigWatcher" -Confirm:$false -ErrorAction SilentlyContinue
        Write-Ok "Task Scheduler task removed"
    } catch { }

    # Remove bin links
    Remove-Item (Join-Path $BinDir "ai-config") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $BinDir "ai-config.bat") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $BinDir "ai-config.ps1") -Force -ErrorAction SilentlyContinue
    Write-Ok "Command links removed"

    # Remove install directory
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force
        Write-Ok "Install directory removed: $InstallDir"
    }

    # Keep config data
    $configDir = Join-Path $env:USERPROFILE ".config\ai-config"
    if (Test-Path $configDir) {
        Write-Info "Config data kept: $configDir"
        Write-Info "To remove: Remove-Item '$configDir' -Recurse -Force"
    }

    Write-Host ""
    Write-Ok "Uninstall complete"
}

if ($Uninstall) {
    Uninstall
} else {
    Install
}
