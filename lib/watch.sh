#!/usr/bin/env bash
# ============================================================
# watch.sh — fswatch 自动监听管理
# ============================================================

WATCH_LOG="$AI_CONFIG_DIR/watch.log"
WATCH_PID="$AI_CONFIG_DIR/watch.pid"
PLIST_NAME="com.ai-config.watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

cmd_watch() {
    local action="${1:-start}"
    case "$action" in
        start)  cmd_watch_start ;;
        stop)   cmd_watch_stop ;;
        status) cmd_watch_status ;;
        log)    cmd_watch_log ;;
        *)
            echo "用法: ai-config watch [start|stop|status|log]"
            echo "  start   启动自动监听（文件变化时自动同步）"
            echo "  stop    停止自动监听"
            echo "  status  查看监听状态"
            echo "  log     查看最近日志"
            ;;
    esac
}

cmd_watch_start() {
    hdr "启动自动监听"

    # 检查 fswatch
    if ! command -v fswatch &>/dev/null; then
        err "fswatch 未安装"
        info "macOS:  brew install fswatch"
        info "Linux:  apt install fswatch / yum install fswatch"
        return 1
    fi

    # macOS: 使用 LaunchAgent
    if [[ "$(uname)" == "Darwin" ]]; then
        watch_start_launchd
    else
        watch_start_background
    fi
}

cmd_watch_stop() {
    hdr "停止自动监听"

    if [[ "$(uname)" == "Darwin" ]] && launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
        launchctl unload "$PLIST_PATH" 2>/dev/null
        ok "LaunchAgent 已停止"
    elif [[ -f "$WATCH_PID" ]]; then
        local pid
        pid=$(cat "$WATCH_PID")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            rm -f "$WATCH_PID"
            ok "Watcher 已停止 (PID: $pid)"
        else
            rm -f "$WATCH_PID"
            warn "Watcher 进程不存在，已清理 PID 文件"
        fi
    else
        warn "Watcher 未在运行"
    fi
}

cmd_watch_status() {
    hdr "监听状态"
    if [[ "$(uname)" == "Darwin" ]] && launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
        echo -e "  状态: ${GREEN}运行中${NC} (LaunchAgent)"
        echo -e "  日志: $WATCH_LOG"
    elif [[ -f "$WATCH_PID" ]] && kill -0 "$(cat "$WATCH_PID")" 2>/dev/null; then
        echo -e "  状态: ${GREEN}运行中${NC} (PID: $(cat "$WATCH_PID"))"
        echo -e "  日志: $WATCH_LOG"
    else
        echo -e "  状态: ${YELLOW}未运行${NC}"
    fi
}

cmd_watch_log() {
    if [[ -f "$WATCH_LOG" ]]; then
        tail -50 "$WATCH_LOG"
    else
        info "暂无日志"
    fi
}

# ---- macOS LaunchAgent ----
watch_start_launchd() {
    # 先生成 watcher 脚本
    watch_generate_script

    # 停止旧实例
    launchctl unload "$PLIST_PATH" 2>/dev/null
    pkill -f "watch_loop\.sh" 2>/dev/null
    sleep 1

    # 生成 plist
    cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${AI_CONFIG_DIR}/watch_loop.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${WATCH_LOG}</string>
    <key>StandardErrorPath</key>
    <string>${AI_CONFIG_DIR}/watch.stderr.log</string>
</dict>
</plist>
PLIST

    launchctl load "$PLIST_PATH" 2>/dev/null
    sleep 2

    if launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
        ok "LaunchAgent 已启动（开机自启）"
        info "日志: tail -f $WATCH_LOG"
    else
        err "LaunchAgent 启动失败"
    fi
}

# ---- 后台进程（Linux 回退方案）----
watch_start_background() {
    watch_generate_script

    # 停止旧实例
    if [[ -f "$WATCH_PID" ]]; then
        kill "$(cat "$WATCH_PID")" 2>/dev/null
        sleep 1
    fi

    nohup bash "$AI_CONFIG_DIR/watch_loop.sh" >> "$WATCH_LOG" 2>&1 &
    echo $! > "$WATCH_PID"
    ok "Watcher 已启动 (PID: $(cat "$WATCH_PID"))"
    info "日志: tail -f $WATCH_LOG"
}

# ---- 生成 watch_loop.sh ----
watch_generate_script() {
    local fswatch_path
    fswatch_path=$(command -v fswatch)
    local ai_config_path
    ai_config_path=$(command -v ai-config 2>/dev/null || echo "$AI_CONFIG_INSTALL_DIR/bin/ai-config")
    local skillshare_path
    skillshare_path=$(command -v skillshare 2>/dev/null || echo "")

    cat > "$AI_CONFIG_DIR/watch_loop.sh" << WATCH_SCRIPT
#!/bin/bash
# 自动生成的 watch loop — 由 ai-config watch start 创建
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\$PATH"

DEBOUNCE=3
last_mcp_sync=0
last_skill_sync=0

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === AI Config Watcher 启动 ==="

while IFS= read -r line; do
    now=\$(date +%s)

    # MCP 配置变化
    if [[ "\$line" == *"mcp.json"* ]]; then
        if (( now - last_mcp_sync > DEBOUNCE )); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP 配置变化，开始同步..."
            "$ai_config_path" sync mcp 2>&1
            last_mcp_sync=\$now
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP 同步完成"
        fi
    fi

    # Skills 目录变化
    if [[ "\$line" == *"skillshare/skills"* ]]; then
        if (( now - last_skill_sync > DEBOUNCE )); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skills 目录变化，开始同步..."
            ${skillshare_path:-skillshare} sync 2>&1
            last_skill_sync=\$now
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skills 同步完成"
        fi
    fi

done < <("$fswatch_path" -r "$AI_CONFIG_DIR" "$HOME/.config/skillshare/skills" 2>/dev/null)
WATCH_SCRIPT

    chmod +x "$AI_CONFIG_DIR/watch_loop.sh"
}
