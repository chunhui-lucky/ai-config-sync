#!/usr/bin/env bash
# ============================================================
# watch.sh — 文件变化自动监听管理（跨平台）
# macOS:  fswatch + LaunchAgent
# Linux:  fswatch + systemd / 后台进程
# Windows: Python watchdog + Task Scheduler (Git Bash)
# ============================================================

WATCH_LOG="$AI_CONFIG_DIR/watch.log"
WATCH_PID="$AI_CONFIG_DIR/watch.pid"
PLIST_NAME="com.ai-config.watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
TASK_NAME="AIConfigWatcher"

cmd_watch() {
    local action="${1:-start}"
    case "$action" in
        start)  cmd_watch_start ;;
        stop)   cmd_watch_stop ;;
        status) cmd_watch_status ;;
        log)    cmd_watch_log ;;
        *)
            echo "Usage: ai-config watch [start|stop|status|log]"
            echo "  start   Start file watcher (auto-sync on changes)"
            echo "  stop    Stop file watcher"
            echo "  status  Show watcher status"
            echo "  log     Show recent logs"
            ;;
    esac
}

cmd_watch_start() {
    hdr "启动自动监听"

    case "$PLATFORM" in
        windows)
            watch_start_windows
            ;;
        wsl)
            watch_start_wsl
            ;;
        macos)
            watch_start_macos
            ;;
        linux)
            watch_start_linux
            ;;
        *)
            err "不支持的平台: $PLATFORM"
            return 1
            ;;
    esac
}

cmd_watch_stop() {
    hdr "停止自动监听"

    case "$PLATFORM" in
        windows)
            watch_stop_windows
            ;;
        macos)
            if launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
                launchctl unload "$PLIST_PATH" 2>/dev/null
                ok "LaunchAgent 已停止"
            else
                warn "LaunchAgent 未在运行"
            fi
            ;;
        *)
            if [[ -f "$WATCH_PID" ]]; then
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
            ;;
    esac
}

cmd_watch_status() {
    hdr "监听状态"

    case "$PLATFORM" in
        windows)
            if powershell.exe -Command "Get-ScheduledTask -TaskName '$TASK_NAME'" &>/dev/null 2>&1; then
                echo -e "  状态: ${GREEN}运行中${NC} (Task Scheduler)"
                echo -e "  日志: $WATCH_LOG"
            else
                echo -e "  状态: ${YELLOW}未运行${NC}"
            fi
            ;;
        macos)
            if launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
                echo -e "  状态: ${GREEN}运行中${NC} (LaunchAgent)"
                echo -e "  日志: $WATCH_LOG"
            else
                echo -e "  状态: ${YELLOW}未运行${NC}"
            fi
            ;;
        *)
            if [[ -f "$WATCH_PID" ]] && kill -0 "$(cat "$WATCH_PID")" 2>/dev/null; then
                echo -e "  状态: ${GREEN}运行中${NC} (PID: $(cat "$WATCH_PID"))"
                echo -e "  日志: $WATCH_LOG"
            else
                echo -e "  状态: ${YELLOW}未运行${NC}"
            fi
            ;;
    esac
}

cmd_watch_log() {
    if [[ -f "$WATCH_LOG" ]]; then
        tail -50 "$WATCH_LOG"
    else
        info "暂无日志"
    fi
}

# ============================================================
# macOS: fswatch + LaunchAgent
# ============================================================
watch_start_macos() {
    if ! command -v fswatch &>/dev/null; then
        err "fswatch 未安装"
        info "安装: brew install fswatch"
        return 1
    fi

    watch_generate_bash_script

    # 停止旧实例
    launchctl unload "$PLIST_PATH" 2>/dev/null
    pkill -f "watch_loop\.sh" 2>/dev/null
    sleep 1

    mkdir -p "$HOME/Library/LaunchAgents"
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

# ============================================================
# Linux: fswatch + 后台进程 / systemd
# ============================================================
watch_start_linux() {
    if ! command -v fswatch &>/dev/null; then
        err "fswatch 未安装"
        info "Ubuntu/Debian: sudo apt install fswatch"
        info "Fedora:        sudo yum install fswatch"
        return 1
    fi

    watch_generate_bash_script

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

# ============================================================
# WSL: fswatch + 后台进程
# ============================================================
watch_start_wsl() {
    watch_start_linux
}

# ============================================================
# Windows (Git Bash): Python watchdog + Task Scheduler
# ============================================================
watch_start_windows() {
    # 确保 watchdog 已安装
    if ! python3 -c "import watchdog" &>/dev/null 2>&1; then
        info "安装 watchdog..."
        pip3 install watchdog 2>/dev/null || pip install watchdog 2>/dev/null
        if ! python3 -c "import watchdog" &>/dev/null 2>&1; then
            err "watchdog 安装失败"
            info "请手动运行: pip install watchdog"
            return 1
        fi
    fi

    watch_generate_python_script

    # 创建 Task Scheduler 任务
    local win_python
    win_python=$(to_win_path "$(command -v python3 2>/dev/null || command -v python)")
    local win_script
    win_script=$(to_win_path "$AI_CONFIG_DIR/watch_loop.py")
    local win_log
    win_log=$(to_win_path "$WATCH_LOG")

    # 删除旧任务
    powershell.exe -Command "Unregister-ScheduledTask -TaskName '$TASK_NAME' -Confirm:\$false" &>/dev/null 2>&1

    # 注册新任务（用户登录时启动）
    powershell.exe -Command "
        \$action = New-ScheduledTaskAction -Execute '$win_python' -Argument '\"$win_script\" >> \"$win_log\" 2>&1'
        \$trigger = New-ScheduledTaskTrigger -AtLogOn
        \$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName '$TASK_NAME' -Action \$action -Trigger \$trigger -Settings \$settings -Description 'AI Config Sync Watcher' -Force
    " &>/dev/null 2>&1

    # 立即启动
    powershell.exe -Command "Start-ScheduledTask -TaskName '$TASK_NAME'" &>/dev/null 2>&1
    sleep 2

    if powershell.exe -Command "Get-ScheduledTask -TaskName '$TASK_NAME'" &>/dev/null 2>&1; then
        ok "Task Scheduler 任务已创建（登录自启）"
        info "日志: cat $WATCH_LOG"
    else
        # fallback: 后台运行
        python3 "$AI_CONFIG_DIR/watch_loop.py" >> "$WATCH_LOG" 2>&1 &
        echo $! > "$WATCH_PID"
        ok "Watcher 后台已启动 (PID: $(cat "$WATCH_PID"))"
        info "Task Scheduler 创建失败，以后台模式运行"
    fi
}

watch_stop_windows() {
    powershell.exe -Command "
        Stop-ScheduledTask -TaskName '$TASK_NAME' -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName '$TASK_NAME' -Confirm:\$false -ErrorAction SilentlyContinue
    " &>/dev/null 2>&1

    if [[ -f "$WATCH_PID" ]]; then
        kill "$(cat "$WATCH_PID")" 2>/dev/null
        rm -f "$WATCH_PID"
    fi
    ok "Watcher 已停止"
}

# ============================================================
# 生成 bash watch 脚本 (macOS / Linux / WSL)
# ============================================================
watch_generate_bash_script() {
    local fswatch_path
    fswatch_path=$(command -v fswatch)
    local ai_config_path
    ai_config_path=$(command -v ai-config 2>/dev/null || echo "$AI_CONFIG_INSTALL_DIR/bin/ai-config")
    local skillshare_path
    skillshare_path=$(command -v skillshare 2>/dev/null || echo "")

    cat > "$AI_CONFIG_DIR/watch_loop.sh" << WATCH_SCRIPT
#!/bin/bash
# Auto-generated by ai-config watch start
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\$PATH"

DEBOUNCE=3
last_mcp_sync=0
last_skill_sync=0

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === AI Config Watcher started ==="

while IFS= read -r line; do
    now=\$(date +%s)

    if [[ "\$line" == *"mcp.json"* ]]; then
        if (( now - last_mcp_sync > DEBOUNCE )); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP config changed, syncing..."
            "$ai_config_path" sync mcp 2>&1
            last_mcp_sync=\$now
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP sync done"
        fi
    fi

    if [[ "\$line" == *"skillshare/skills"* ]]; then
        if (( now - last_skill_sync > DEBOUNCE )); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skills changed, syncing..."
            ${skillshare_path:-skillshare} sync 2>&1
            last_skill_sync=\$now
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skills sync done"
        fi
    fi

done < <("$fswatch_path" -r "$AI_CONFIG_DIR" "$HOME/.config/skillshare/skills" 2>/dev/null)
WATCH_SCRIPT

    chmod +x "$AI_CONFIG_DIR/watch_loop.sh"
}

# ============================================================
# 生成 Python watch 脚本 (Windows)
# ============================================================
watch_generate_python_script() {
    local ai_config_path
    ai_config_path=$(command -v ai-config 2>/dev/null || echo "$AI_CONFIG_INSTALL_DIR/bin/ai-config")
    local skillshare_path
    skillshare_path=$(command -v skillshare 2>/dev/null || echo "skillshare")

    cat > "$AI_CONFIG_DIR/watch_loop.py" << 'PYTHON_HEADER'
#!/usr/bin/env python3
"""AI Config Watcher — cross-platform file watcher using watchdog."""
import sys
import time
import subprocess
import os
from pathlib import Path

try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
except ImportError:
    print("Error: watchdog not installed. Run: pip install watchdog")
    sys.exit(1)

PYTHON_HEADER

    cat >> "$AI_CONFIG_DIR/watch_loop.py" << PYTHON_VARS
AI_CONFIG_DIR = r"$AI_CONFIG_DIR"
SKILLS_DIR = os.path.expanduser(r"~/.config/skillshare/skills")
AI_CONFIG_BIN = r"$ai_config_path"
SKILLSHARE_BIN = r"$skillshare_path"
DEBOUNCE = 3

last_mcp_sync = 0
last_skill_sync = 0
PYTHON_VARS

    cat >> "$AI_CONFIG_DIR/watch_loop.py" << 'PYTHON_BODY'

class ConfigHandler(FileSystemEventHandler):
    def on_any_event(self, event):
        global last_mcp_sync, last_skill_sync
        now = time.time()
        src = event.src_path

        if "mcp.json" in src and (now - last_mcp_sync > DEBOUNCE):
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] MCP config changed, syncing...")
            subprocess.run(["bash", AI_CONFIG_BIN, "sync", "mcp"], capture_output=True, text=True)
            last_mcp_sync = now
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] MCP sync done")

        if "skillshare" in src and "skills" in src and (now - last_skill_sync > DEBOUNCE):
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Skills changed, syncing...")
            subprocess.run(["bash", "-c", f"{SKILLSHARE_BIN} sync"], capture_output=True, text=True)
            last_skill_sync = now
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Skills sync done")

if __name__ == "__main__":
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] === AI Config Watcher started (watchdog) ===")

    handler = ConfigHandler()
    observer = Observer()

    observer.schedule(handler, AI_CONFIG_DIR, recursive=True)
    if os.path.isdir(SKILLS_DIR):
        observer.schedule(handler, SKILLS_DIR, recursive=True)

    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
PYTHON_BODY
}
