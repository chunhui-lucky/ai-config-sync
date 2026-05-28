#!/usr/bin/env bash
# ============================================================
# ai-config-sync installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/chunhui-lucky/ai-config-sync/main/install.sh | bash
#   bash install.sh [--uninstall]
#
# Supports: macOS, Linux, WSL, Windows (Git Bash)
# ============================================================
set -euo pipefail

REPO_URL="${AI_CONFIG_REPO:-https://github.com/chunhui-lucky/ai-config-sync}"
INSTALL_DIR="$HOME/.config/ai-config-sync"
BIN_DIR=""
SCRIPT_NAME="ai-config"

# ---- Platform detection ----
case "$(uname -s 2>/dev/null)" in
    Darwin*)  PLATFORM="macos" ;;
    Linux*)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            PLATFORM="wsl"
        else
            PLATFORM="linux"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    *) PLATFORM="unknown" ;;
esac

# ---- Colors ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

# ---- Find bin directory ----
find_bin_dir() {
    if [[ "$PLATFORM" == "windows" ]]; then
        mkdir -p "$HOME/.local/bin"
        BIN_DIR="$HOME/.local/bin"
    elif [[ -d "$HOME/.local/bin" ]] || [[ -w "$HOME" ]]; then
        mkdir -p "$HOME/.local/bin"
        BIN_DIR="$HOME/.local/bin"
    elif [[ -d "/usr/local/bin" ]] && [[ -w "/usr/local/bin" ]]; then
        BIN_DIR="/usr/local/bin"
    else
        mkdir -p "$HOME/.local/bin"
        BIN_DIR="$HOME/.local/bin"
    fi
}

# ---- Check PATH ----
check_path() {
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "$BIN_DIR not in PATH"

        if [[ "$PLATFORM" == "windows" ]]; then
            # Windows Git Bash: add to .bashrc / .bash_profile
            local rc="$HOME/.bashrc"
            [[ -f "$HOME/.bash_profile" ]] && rc="$HOME/.bash_profile"
            local path_line="export PATH=\"$BIN_DIR:\$PATH\""
            if ! grep -qF "$BIN_DIR" "$rc" 2>/dev/null; then
                echo "" >> "$rc"
                echo "# ai-config-sync" >> "$rc"
                echo "$path_line" >> "$rc"
                ok "Added $BIN_DIR to $rc"
                info "Run: source $rc"
            fi
        else
            local shell_rc=""
            if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "${SHELL:-/bin/bash}")" == "zsh" ]]; then
                shell_rc="$HOME/.zshrc"
            elif [[ -n "${BASH_VERSION:-}" ]]; then
                shell_rc="$HOME/.bashrc"
            fi
            if [[ -n "$shell_rc" ]]; then
                local path_line="export PATH=\"$BIN_DIR:\$PATH\""
                if ! grep -qF "$BIN_DIR" "$shell_rc" 2>/dev/null; then
                    echo "" >> "$shell_rc"
                    echo "# ai-config-sync" >> "$shell_rc"
                    echo "$path_line" >> "$shell_rc"
                    ok "Added $BIN_DIR to $shell_rc"
                    info "Run: source $shell_rc"
                fi
            fi
        fi
    fi
}

# ---- Install ----
do_install() {
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   ai-config-sync installer            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""
    info "Platform: $PLATFORM"

    # Check dependencies
    echo -e "\n  ${BLUE}[Dependencies]${NC}"
    if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        err "Python 3 not found"
        if [[ "$PLATFORM" == "windows" ]]; then
            info "Download: https://www.python.org/downloads/"
        elif [[ "$PLATFORM" == "macos" ]]; then
            info "brew install python3"
        else
            info "sudo apt install python3"
        fi
        exit 1
    fi
    ok "python3"

    if command -v git &>/dev/null; then
        ok "git"
    else
        err "git not found"
        exit 1
    fi

    # Install/update
    echo -e "\n  ${BLUE}[Install]${NC}"
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        info "Already installed, updating..."
        cd "$INSTALL_DIR"
        git pull --quiet 2>/dev/null || warn "Update failed, using local version"
        ok "Updated: $INSTALL_DIR"
    elif [[ -d "$INSTALL_DIR" ]]; then
        warn "Directory exists but not a git repo, backing up"
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M%S)"
        git clone --quiet "$REPO_URL" "$INSTALL_DIR"
        ok "Installed: $INSTALL_DIR"
    else
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone --quiet "$REPO_URL" "$INSTALL_DIR"
        ok "Installed: $INSTALL_DIR"
    fi

    # Create bin link
    find_bin_dir
    echo -e "\n  ${BLUE}[Linking]${NC}"
    chmod +x "$INSTALL_DIR/bin/$SCRIPT_NAME"

    local link_target="$BIN_DIR/$SCRIPT_NAME"
    if [[ -L "$link_target" ]] || [[ -f "$link_target" ]]; then
        rm -f "$link_target"
    fi

    if [[ "$PLATFORM" == "windows" ]]; then
        # On Windows Git Bash, use a wrapper script that works in both bash and cmd
        cp "$INSTALL_DIR/bin/$SCRIPT_NAME" "$link_target"
        chmod +x "$link_target"
        # Also create a .bat wrapper for cmd.exe users
        local bat_target="$BIN_DIR/$SCRIPT_NAME.bat"
        cat > "$bat_target" << 'BAT_EOF'
@echo off
bash "%~dp0ai-config" %*
BAT_EOF
        ok "$SCRIPT_NAME → $link_target (+ .bat wrapper)"
    else
        ln -sf "$INSTALL_DIR/bin/$SCRIPT_NAME" "$link_target"
        ok "$SCRIPT_NAME → $link_target"
    fi

    # Check PATH
    check_path

    export AI_CONFIG_INSTALL_DIR="$INSTALL_DIR"

    # Windows-specific: install watchdog for file watching
    if [[ "$PLATFORM" == "windows" ]]; then
        echo -e "\n  ${BLUE}[Windows extras]${NC}"
        if ! python3 -c "import watchdog" &>/dev/null 2>&1; then
            info "Installing watchdog (for file watching)..."
            pip3 install watchdog 2>/dev/null || pip install watchdog 2>/dev/null || true
            if python3 -c "import watchdog" &>/dev/null 2>&1; then
                ok "watchdog installed"
            else
                warn "watchdog install failed (auto-watch may not work)"
                info "Try: pip install watchdog"
            fi
        else
            ok "watchdog (already installed)"
        fi
    fi

    echo -e "\n  ${GREEN}Done!${NC}"
    echo ""
    info "Get started:"
    echo ""
    echo "    ai-config init       # Initialize (scan & merge existing configs)"
    echo "    ai-config sync       # Sync configs to all tools"
    echo "    ai-config status     # Check status"
    echo "    ai-config help       # All commands"
    echo ""
}

# ---- Uninstall ----
do_uninstall() {
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   ai-config-sync uninstaller          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""

    # Stop watcher
    case "$PLATFORM" in
        macos)
            launchctl unload "$HOME/Library/LaunchAgents/com.ai-config.watcher.plist" 2>/dev/null
            rm -f "$HOME/Library/LaunchAgents/com.ai-config.watcher.plist"
            ok "LaunchAgent stopped"
            ;;
        windows)
            powershell.exe -Command "
                Stop-ScheduledTask -TaskName 'AIConfigWatcher' -ErrorAction SilentlyContinue
                Unregister-ScheduledTask -TaskName 'AIConfigWatcher' -Confirm:\$false -ErrorAction SilentlyContinue
            " &>/dev/null 2>&1
            ok "Task Scheduler task removed"
            ;;
    esac

    # Remove bin link
    find_bin_dir
    rm -f "$BIN_DIR/$SCRIPT_NAME" "$BIN_DIR/$SCRIPT_NAME.bat"
    ok "Command link removed"

    # Remove install directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        ok "Install directory removed: $INSTALL_DIR"
    fi

    # Keep config data
    if [[ -d "$HOME/.config/ai-config" ]]; then
        info "Config data kept: ~/.config/ai-config/"
        info "To remove: rm -rf ~/.config/ai-config/"
    fi

    echo ""
    ok "Uninstall complete"
}

# ---- Main ----
case "${1:-}" in
    --uninstall|-u) do_uninstall ;;
    --help|-h)
        echo "ai-config-sync installer"
        echo ""
        echo "Usage:"
        echo "  bash install.sh              Install"
        echo "  bash install.sh --uninstall  Uninstall"
        echo ""
        echo "Environment:"
        echo "  AI_CONFIG_REPO    Git repo URL (default: $REPO_URL)"
        echo ""
        echo "Supports: macOS, Linux, WSL, Windows (Git Bash)"
        ;;
    *) do_install ;;
esac
