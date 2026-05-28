#!/usr/bin/env bash
# ============================================================
# sync.sh — 将统一配置同步到所有已安装的工具
# ============================================================

cmd_sync() {
    local scope="${1:-all}"  # all | mcp | rules

    if [[ "$scope" == "all" ]]; then
        banner
        sync_mcp
        sync_rules
        echo -e "\n${GREEN}同步完成!${NC}"
    elif [[ "$scope" == "mcp" ]]; then
        sync_mcp
    elif [[ "$scope" == "rules" ]]; then
        sync_rules
    else
        err "未知范围: $scope"
        echo "用法: ai-config sync [mcp|rules|all]"
        return 1
    fi
}

sync_mcp() {
    hdr "同步 MCP 配置"
    if [[ ! -f "$MCP_SRC" ]]; then
        err "找不到 $MCP_SRC，请先运行 ai-config init"
        return 1
    fi

    local count
    count=$(json_count "$MCP_SRC" "mcpServers")
    info "共 $count 个 MCP server"

    load_tool_plugins
    for plugin in "${TOOL_PLUGINS[@]}"; do
        local detected
        detected=$(_run_plugin "$plugin" 'tool_detect && echo yes || echo no')
        if [[ "$detected" != "yes" ]]; then
            continue
        fi

        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        echo -e "\n  ${BLUE}[$name]${NC}"
        (
            source "$AI_CONFIG_INSTALL_DIR/lib/utils.sh"
            source "$plugin"
            tool_sync_mcp "$MCP_SRC"
        )
    done
}

sync_rules() {
    hdr "同步 Rules"
    if [[ ! -f "$RULES_SRC" ]]; then
        err "找不到 $RULES_SRC，请先运行 ai-config init"
        return 1
    fi

    load_tool_plugins
    for plugin in "${TOOL_PLUGINS[@]}"; do
        local detected
        detected=$(_run_plugin "$plugin" 'tool_detect && echo yes || echo no')
        if [[ "$detected" != "yes" ]]; then
            continue
        fi

        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        echo -e "\n  ${BLUE}[$name]${NC}"
        (
            source "$AI_CONFIG_INSTALL_DIR/lib/utils.sh"
            source "$plugin"
            tool_sync_rules "$RULES_SRC"
        )
    done
}
