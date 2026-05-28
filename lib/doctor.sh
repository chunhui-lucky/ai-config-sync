#!/usr/bin/env bash
# ============================================================
# doctor.sh — 检查环境健康状态
# ============================================================

cmd_doctor() {
    banner
    hdr "环境检查"

    local issues=0

    # ---- Python3 ----
    echo -e "\n  ${BLUE}[依赖]${NC}"
    if command -v python3 &>/dev/null; then
        ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"
    else
        err "python3 未安装"
        ((issues++))
    fi

    # ---- fswatch ----
    if command -v fswatch &>/dev/null; then
        ok "fswatch $(fswatch --version 2>&1 | head -1)"
    else
        warn "fswatch 未安装（自动监听不可用）"
        info "安装: brew install fswatch"
    fi

    # ---- skillshare ----
    if command -v skillshare &>/dev/null; then
        ok "skillshare (已安装)"
    else
        info "skillshare 未安装（Skills 同步不可用，可手动安装）"
    fi

    # ---- 配置仓库 ----
    echo -e "\n  ${BLUE}[配置仓库]${NC}"
    if [[ -d "$AI_CONFIG_DIR" ]]; then
        ok "目录存在: $AI_CONFIG_DIR"
    else
        err "目录不存在: $AI_CONFIG_DIR"
        info "运行 ai-config init 创建"
        ((issues++))
    fi

    if [[ -f "$MCP_SRC" ]]; then
        local mcp_count
        mcp_count=$(json_count "$MCP_SRC" "mcpServers")
        ok "mcp.json ($mcp_count 个 server)"
    else
        warn "mcp.json 不存在"
        ((issues++))
    fi

    if [[ -f "$RULES_SRC" ]]; then
        ok "rules.md 存在"
    else
        warn "rules.md 不存在"
        ((issues++))
    fi

    # ---- AI 工具检测 ----
    echo -e "\n  ${BLUE}[AI 工具]${NC}"
    load_tool_plugins
    local tool_count=0
    for plugin in "${TOOL_PLUGINS[@]}"; do
        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        local detected
        detected=$(_run_plugin "$plugin" 'tool_detect && echo yes || echo no')
        if [[ "$detected" == "yes" ]]; then
            ok "$name"
            ((tool_count++))
        else
            info "$name (未检测到)"
        fi
    done

    if [[ $tool_count -eq 0 ]]; then
        err "未检测到任何 AI 工具"
        ((issues++))
    fi

    # ---- Watcher ----
    echo -e "\n  ${BLUE}[自动监听]${NC}"
    if [[ "$(uname)" == "Darwin" ]] && launchctl list 2>/dev/null | grep -q "com.ai-config.watcher"; then
        ok "fswatch watcher 运行中"
    elif [[ -f "$AI_CONFIG_DIR/watch.pid" ]] && kill -0 "$(cat "$AI_CONFIG_DIR/watch.pid")" 2>/dev/null; then
        ok "watcher 运行中 (PID: $(cat "$AI_CONFIG_DIR/watch.pid"))"
    else
        info "watcher 未运行（可选）"
    fi

    # ---- 总结 ----
    echo ""
    if [[ $issues -eq 0 ]]; then
        ok "所有检查通过！"
    else
        warn "发现 $issues 个问题"
    fi
}
