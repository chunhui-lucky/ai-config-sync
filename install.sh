#!/usr/bin/env bash
# ============================================================
# ai-config-sync 安装器
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/user/ai-config-sync/main/install.sh | bash
#   bash install.sh [--uninstall]
# ============================================================
set -euo pipefail

REPO_URL="${AI_CONFIG_REPO:-https://github.com/user/ai-config-sync}"
INSTALL_DIR="$HOME/.config/ai-config-sync"
BIN_DIR=""
SCRIPT_NAME="ai-config"

# ---- 颜色 ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

# ---- 检测 bin 目录 ----
find_bin_dir() {
    # 优先级：~/.local/bin > /usr/local/bin > ~/bin
    if [[ -d "$HOME/.local/bin" ]] || [[ -w "$HOME" ]]; then
        mkdir -p "$HOME/.local/bin"
        BIN_DIR="$HOME/.local/bin"
    elif [[ -d "/usr/local/bin" ]] && [[ -w "/usr/local/bin" ]]; then
        BIN_DIR="/usr/local/bin"
    elif [[ -d "$HOME/bin" ]]; then
        BIN_DIR="$HOME/bin"
    else
        mkdir -p "$HOME/.local/bin"
        BIN_DIR="$HOME/.local/bin"
    fi
}

# ---- 检查 PATH ----
check_path() {
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "$BIN_DIR 不在 PATH 中"
        # 尝试添加到 shell 配置
        local shell_rc=""
        if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "$SHELL")" == "zsh" ]]; then
            shell_rc="$HOME/.zshrc"
        elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$(basename "$SHELL")" == "bash" ]]; then
            shell_rc="$HOME/.bashrc"
        fi

        if [[ -n "$shell_rc" ]]; then
            local path_line="export PATH=\"$BIN_DIR:\$PATH\""
            if ! grep -qF "$BIN_DIR" "$shell_rc" 2>/dev/null; then
                echo "" >> "$shell_rc"
                echo "# ai-config-sync" >> "$shell_rc"
                echo "$path_line" >> "$shell_rc"
                ok "已添加 $BIN_DIR 到 $shell_rc"
                info "请运行: source $shell_rc"
            fi
        fi
    fi
}

# ---- 安装 ----
do_install() {
    echo -e "${BLUE}╔══════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   ai-config-sync 安装器           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════╝${NC}"
    echo ""

    # 检查依赖
    echo -e "  ${BLUE}[检查依赖]${NC}"
    if ! command -v python3 &>/dev/null; then
        err "python3 未安装，请先安装 Python 3"
        exit 1
    fi
    ok "python3"

    if command -v git &>/dev/null; then
        ok "git"
    else
        err "git 未安装"
        exit 1
    fi

    # 安装/更新
    echo -e "\n  ${BLUE}[安装]${NC}"
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        info "已安装，更新中..."
        cd "$INSTALL_DIR"
        git pull --quiet 2>/dev/null || warn "更新失败，使用本地版本"
        ok "已更新: $INSTALL_DIR"
    elif [[ -d "$INSTALL_DIR" ]]; then
        warn "目录已存在但非 git 仓库，备份后重新安装"
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M%S)"
        git clone --quiet "$REPO_URL" "$INSTALL_DIR"
        ok "已安装: $INSTALL_DIR"
    else
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone --quiet "$REPO_URL" "$INSTALL_DIR"
        ok "已安装: $INSTALL_DIR"
    fi

    # 创建 bin 链接
    find_bin_dir
    echo -e "\n  ${BLUE}[创建命令链接]${NC}"
    chmod +x "$INSTALL_DIR/bin/$SCRIPT_NAME"

    local link_target="$BIN_DIR/$SCRIPT_NAME"
    if [[ -L "$link_target" ]] || [[ -f "$link_target" ]]; then
        rm -f "$link_target"
    fi
    ln -sf "$INSTALL_DIR/bin/$SCRIPT_NAME" "$link_target"
    ok "$SCRIPT_NAME → $link_target"

    # 检查 PATH
    check_path

    # 设置安装目录环境变量
    export AI_CONFIG_INSTALL_DIR="$INSTALL_DIR"

    echo -e "\n  ${GREEN}安装完成!${NC}"
    echo ""
    info "运行以下命令开始使用:"
    echo ""
    echo "    ai-config init       # 初始化（扫描已有配置并合并）"
    echo "    ai-config sync       # 同步配置到所有工具"
    echo "    ai-config status     # 查看状态"
    echo "    ai-config help       # 查看所有命令"
    echo ""
}

# ---- 卸载 ----
do_uninstall() {
    echo -e "${BLUE}╔══════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   ai-config-sync 卸载器           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════╝${NC}"
    echo ""

    # 停止 watcher
    if [[ "$(uname)" == "Darwin" ]]; then
        launchctl unload "$HOME/Library/LaunchAgents/com.ai-config.watcher.plist" 2>/dev/null
        rm -f "$HOME/Library/LaunchAgents/com.ai-config.watcher.plist"
        ok "LaunchAgent 已停止"
    fi

    # 移除 bin 链接
    find_bin_dir
    rm -f "$BIN_DIR/$SCRIPT_NAME"
    ok "命令链接已移除"

    # 移除安装目录
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        ok "安装目录已移除: $INSTALL_DIR"
    fi

    # 保留配置数据
    if [[ -d "$HOME/.config/ai-config" ]]; then
        info "配置数据保留: ~/.config/ai-config/"
        info "如需完全清除: rm -rf ~/.config/ai-config/"
    fi

    echo ""
    ok "卸载完成"
}

# ---- 主入口 ----
case "${1:-}" in
    --uninstall|-u) do_uninstall ;;
    --help|-h)
        echo "ai-config-sync 安装器"
        echo ""
        echo "用法:"
        echo "  bash install.sh              安装"
        echo "  bash install.sh --uninstall  卸载"
        echo ""
        echo "环境变量:"
        echo "  AI_CONFIG_REPO    Git 仓库 URL（默认: $REPO_URL）"
        ;;
    *) do_install ;;
esac
