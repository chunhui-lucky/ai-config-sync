#!/usr/bin/env bash
# ============================================================
# status.sh — 查看配置同步状态
# ============================================================

cmd_status() {
    banner

    # ---- 配置仓库 ----
    hdr "配置仓库"
    echo -e "  目录: $AI_CONFIG_DIR"
    if [[ -d "$AI_CONFIG_DIR" ]]; then
        if [[ -f "$MCP_SRC" ]]; then
            local mcp_count
            mcp_count=$(json_count "$MCP_SRC" "mcpServers")
            echo -e "  MCP:   ${GREEN}✓${NC} $mcp_count 个 server"
        else
            echo -e "  MCP:   ${YELLOW}⚠ mcp.json 不存在${NC}"
        fi
        if [[ -f "$RULES_SRC" ]]; then
            local rules_lines
            rules_lines=$(wc -l < "$RULES_SRC" | tr -d ' ')
            echo -e "  Rules: ${GREEN}✓${NC} $rules_lines 行"
        else
            echo -e "  Rules: ${YELLOW}⚠ rules.md 不存在${NC}"
        fi
    else
        err "配置仓库不存在，请先运行 ai-config init"
        return 1
    fi

    # ---- 各工具状态 ----
    load_tool_plugins
    for plugin in "${TOOL_PLUGINS[@]}"; do
        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        local detected
        detected=$(_run_plugin "$plugin" 'tool_detect && echo yes || echo no')

        if [[ "$detected" != "yes" ]]; then
            hdr "$name (未检测到)"
            continue
        fi

        hdr "$name"
        echo -e "\n  ${BLUE}[MCP]${NC}"
        local mcp_status
        mcp_status=$(_run_plugin "$plugin" 'tool_status_mcp' 2>/dev/null)
        echo -e "    $mcp_status"

        echo -e "\n  ${BLUE}[Rules]${NC}"
        local rules_status
        rules_status=$(_run_plugin "$plugin" 'tool_status_rules' 2>/dev/null)
        echo -e "    $rules_status"
    done

    # ---- Watcher 状态 ----
    hdr "自动监听"
    if launchctl list 2>/dev/null | grep -q "com.ai-config.watcher"; then
        echo -e "  ${GREEN}✓${NC} fswatch watcher 运行中"
    elif [[ -f "$AI_CONFIG_DIR/watch.pid" ]] && kill -0 "$(cat "$AI_CONFIG_DIR/watch.pid")" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} watcher 运行中 (PID: $(cat "$AI_CONFIG_DIR/watch.pid"))"
    else
        echo -e "  ${YELLOW}⚠${NC} watcher 未运行"
        info "运行 ai-config watch start 启动"
    fi
}
