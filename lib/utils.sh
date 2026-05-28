#!/usr/bin/env bash
# ============================================================
# utils.sh — 公共函数库：颜色、备份、符号链接、日志、交互
# ============================================================

# ---- 平台检测 ----
detect_platform() {
    case "$(uname -s 2>/dev/null)" in
        Darwin*)  PLATFORM="macos" ;;
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
            else
                PLATFORM="linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM="windows"
            ;;
        *)
            PLATFORM="unknown"
            ;;
    esac
}
detect_platform

# Windows 下把 Unix 路径转成 Windows 路径（给 cmd.exe / powershell 用）
to_win_path() {
    local p="$1"
    if [[ "$PLATFORM" == "windows" ]]; then
        # /c/Users/foo → C:\Users\foo
        echo "$p" | sed 's|^/\([a-zA-Z]\)/|\U\1:\\|;s|/|\\|g'
    elif [[ "$PLATFORM" == "wsl" ]]; then
        wslpath -w "$p" 2>/dev/null || echo "$p"
    else
        echo "$p"
    fi
}

# ---- 颜色 ----
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ---- 输出 ----
ok()     { echo -e "  ${GREEN}✓${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()    { echo -e "  ${RED}✗${NC} $1"; }
hdr()    { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
info()   { echo -e "  ${CYAN}ℹ${NC} $1"; }

banner() {
    echo -e "${BLUE}╔══════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      ai-config-sync  v${VERSION:-0.1.0}    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════╝${NC}"
}

# ---- 配置目录 ----
AI_CONFIG_DIR="${AI_CONFIG_DIR:-$HOME/.config/ai-config}"
MCP_SRC="$AI_CONFIG_DIR/mcp.json"
RULES_SRC="$AI_CONFIG_DIR/rules.md"

# ---- 备份 ----
backup_file() {
    local f="$1"
    if [[ -e "$f" && ! -L "$f" ]]; then
        local bak="${f}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$f" "$bak"
        ok "已备份 $(basename "$f") → $(basename "$bak")"
    fi
}

# ---- 符号链接 ----
# 跨平台：macOS/Linux 用 ln -sf，Windows Git Bash 用 mklink（junction），WSL 用 ln -sf
safe_symlink() {
    local src="$1" dst="$2" label="$3"

    # 已经是正确链接
    if [[ -L "$dst" ]] || [[ -e "$dst" && "$(readlink "$dst" 2>/dev/null)" == "$src" ]]; then
        local cur
        cur=$(readlink "$dst" 2>/dev/null)
        if [[ "$cur" == "$src" ]]; then
            ok "$label → 已链接"
            return 0
        fi
    fi

    # 清理旧目标
    if [[ -L "$dst" ]] || [[ -e "$dst" ]]; then
        if [[ ! -L "$dst" ]]; then
            backup_file "$dst"
        fi
        rm -rf "$dst"
    fi

    mkdir -p "$(dirname "$dst")"

    case "$PLATFORM" in
        windows)
            # Windows (Git Bash): 用 cmd.exe mklink 创建 junction（不需要管理员权限）
            local win_src win_dst
            win_src=$(to_win_path "$src")
            win_dst=$(to_win_path "$dst")
            if cmd.exe /c "mklink /J \"$win_dst\" \"$win_src\"" &>/dev/null; then
                ok "$label → $(basename "$src") (junction)"
            else
                # fallback: 直接复制
                cp "$src" "$dst"
                ok "$label → $(basename "$src") (复制，symlink 不可用)"
            fi
            ;;
        wsl)
            # WSL: 普通 symlink 即可（Windows 侧能识别）
            ln -sf "$src" "$dst"
            ok "$label → $(basename "$src")"
            ;;
        *)
            # macOS / Linux
            ln -sf "$src" "$dst"
            ok "$label → $(basename "$src")"
            ;;
    esac
}

# ---- 交互 ----
ask_yes_no() {
    local prompt="$1" default="${2:-y}"
    local choices
    if [[ "$default" == "y" ]]; then
        choices="[Y/n]"
    else
        choices="[y/N]"
    fi
    echo -ne "  ${CYAN}?${NC} $prompt $choices "
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    echo -e "  ${CYAN}?${NC} $prompt"
    local i
    for i in "${!options[@]}"; do
        echo -e "    $((i+1))) ${options[$i]}"
    done
    echo -ne "  选择 [1-${#options[@]}]: "
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        echo "${options[$((choice-1))]}"
        return 0
    fi
    return 1
}

# ---- 符号链接状态检查（供插件使用）----
check_link_status() {
    local path="$1" expected="$2"
    if [[ -L "$path" ]]; then
        local target
        target=$(readlink "$path")
        if [[ -n "$expected" && "$target" == "$expected" ]]; then
            echo "✓ 已链接"
        else
            echo "⚠ 链接到其他 → $target"
        fi
    elif [[ "$PLATFORM" == "windows" && -d "$path" ]]; then
        # Windows junction 不会被 readlink 识别，检查是否指向目标
        echo "✓ 已链接 (Windows junction)"
    elif [[ -e "$path" ]]; then
        echo "⚠ 独立文件（未链接）"
    else
        echo "✗ 不存在"
    fi
}

# ---- 在子 shell 中安全执行插件函数 ----
_run_plugin() {
    local plugin="$1"
    shift
    local utils="$AI_CONFIG_INSTALL_DIR/lib/utils.sh"
    bash -c "source '$utils'; source '$plugin'; $*"
}

# ---- 工具检测 ----
detect_tools() {
    local -n _detected=$1
    _detected=()

    local plugin_dir="$AI_CONFIG_INSTALL_DIR/lib/tools"
    for plugin in "$plugin_dir"/*.sh; do
        [[ -f "$plugin" ]] || continue
        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        local ok
        ok=$(_run_plugin "$plugin" 'tool_detect && echo yes || echo no')
        if [[ "$ok" == "yes" ]]; then
            _detected+=("$name")
        fi
    done
}

# ---- 加载工具插件 ----
load_tool_plugins() {
    local plugin_dir="$AI_CONFIG_INSTALL_DIR/lib/tools"
    TOOL_PLUGINS=()
    for plugin in "$plugin_dir"/*.sh; do
        [[ -f "$plugin" ]] || continue
        TOOL_PLUGINS+=("$plugin")
    done
}

# ---- JSON 工具 ----
json_keys() {
    python3 -c "import json; [print(k) for k in json.load(open('$1'))['$2']]" 2>/dev/null
}

json_count() {
    python3 -c "import json; print(len(json.load(open('$1'))['$2']))" 2>/dev/null
}
