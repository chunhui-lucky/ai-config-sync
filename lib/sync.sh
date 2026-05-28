#!/usr/bin/env bash
# ============================================================
# sync.sh — 将统一配置同步到所有已安装的工具
# ============================================================

cmd_sync() {
    local scope="${1:-all}"  # all | mcp | rules | project
    local project_path=""

    # 解析 --project 参数
    if [[ "$2" == "--project" && -n "$3" ]]; then
        project_path="$3"
    fi

    if [[ "$scope" == "all" ]]; then
        banner
        sync_mcp
        sync_rules
        if [[ -n "$project_path" ]]; then
            sync_project "$project_path"
        fi
        echo -e "\n${GREEN}同步完成!${NC}"
    elif [[ "$scope" == "mcp" ]]; then
        sync_mcp
    elif [[ "$scope" == "rules" ]]; then
        sync_rules
    elif [[ "$scope" == "project" ]]; then
        if [[ -z "$project_path" ]]; then
            err "请指定项目路径: ai-config sync project --project <path>"
            return 1
        fi
        sync_project "$project_path"
    else
        err "未知范围: $scope"
        echo "用法: ai-config sync [mcp|rules|project|all] [--project <path>]"
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

sync_project() {
    local project_path="$1"
    hdr "同步项目级配置"
    info "项目路径: $project_path"

    if [[ ! -d "$project_path" ]]; then
        err "项目目录不存在: $project_path"
        return 1
    fi

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
            if declare -f tool_sync_project_rules &>/dev/null; then
                tool_sync_project_rules "$project_path" "$RULES_SRC"
            else
                info "不支持项目级配置"
            fi
        )
    done
}
