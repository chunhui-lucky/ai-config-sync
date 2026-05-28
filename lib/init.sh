#!/usr/bin/env bash
# ============================================================
# init.sh — 初始化统一配置仓库
# 扫描已有工具配置，合并到 ~/.config/ai-config/
# ============================================================

cmd_init() {
    local source_tool="${1:-}"

    banner
    hdr "初始化统一配置仓库"
    info "配置目录: $AI_CONFIG_DIR"
    mkdir -p "$AI_CONFIG_DIR"

    # ---- 检测已安装的工具 ----
    hdr "检测已安装的 AI 工具"
    local detected=()
    load_tool_plugins
    for plugin in "${TOOL_PLUGINS[@]}"; do
        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        local is_detected
        is_detected=$(_run_plugin "$plugin" 'tool_detect && echo yes || echo no')
        if [[ "$is_detected" == "yes" ]]; then
            ok "发现: $name"
            detected+=("$name")
        fi
    done

    if [[ ${#detected[@]} -eq 0 ]]; then
        err "未检测到任何已安装的 AI 工具"
        err "请确保至少安装了 Codex、Cursor 或 Claude Code 中的一个"
        return 1
    fi

    # ---- 选择 source-of-truth ----
    if [[ -z "$source_tool" ]]; then
        hdr "选择配置源"
        info "多个工具都有已有配置，请选择一个作为基准（冲突时保留此工具的配置）"

        # 默认推荐 codex
        local default_idx=0
        for i in "${!detected[@]}"; do
            if [[ "${detected[$i]}" == "codex" ]]; then
                default_idx=$i
                break
            fi
        done

        echo -e "  ${CYAN}?${NC} 选择 source-of-truth:"
        for i in "${!detected[@]}"; do
            local marker=""
            [[ $i -eq $default_idx ]] && marker=" (推荐)"
            echo -e "    $((i+1))) ${detected[$i]}${marker}"
        done
        echo -ne "  选择 [1-${#detected[@]}] (默认 $((default_idx+1))): "
        read -r choice
        choice="${choice:-$((default_idx+1))}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#detected[@]} )); then
            source_tool="${detected[$((choice-1))]}"
        else
            source_tool="${detected[$default_idx]}"
        fi
    fi
    ok "配置源: $source_tool"

    # ---- 合并 MCP 配置 ----
    hdr "合并 MCP 配置"
    merge_mcp_configs "$source_tool"

    # ---- 合并 Rules ----
    hdr "合并 Rules"
    merge_rules "$source_tool"

    # ---- 备份原始配置 ----
    hdr "备份原始配置"
    backup_original_configs

    # ---- 执行首次同步 ----
    hdr "执行首次同步"
    cmd_sync

    # ---- 询问是否安装 watcher ----
    if command -v fswatch &>/dev/null; then
        echo ""
        if ask_yes_no "是否启动自动监听（文件变化时自动同步）？"; then
            cmd_watch start
        fi
    else
        echo ""
        info "未安装 fswatch，跳过自动监听"
        info "可运行: brew install fswatch && ai-config watch start"
    fi

    echo ""
    ok "初始化完成！"
    info "编辑配置:  vim $AI_CONFIG_DIR/mcp.json"
    info "编辑规则:  vim $AI_CONFIG_DIR/rules.md"
    info "手动同步:  ai-config sync"
    info "查看状态:  ai-config status"
}

# ---- MCP 合并 ----
merge_mcp_configs() {
    local source_tool="$1"
    local merged='{"mcpServers":{}}'

    # 按非 source → source 的顺序合并，后写入的覆盖先写入的
    local order=()
    for plugin in "${TOOL_PLUGINS[@]}"; do
        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        [[ "$name" != "$source_tool" ]] && order+=("$plugin")
    done
    for plugin in "${TOOL_PLUGINS[@]}"; do
        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        [[ "$name" == "$source_tool" ]] && order+=("$plugin")
    done

    for plugin in "${order[@]}"; do
        local mcp_json
        mcp_json=$(_run_plugin "$plugin" 'tool_get_mcp_source' 2>/dev/null)
        if [[ -n "$mcp_json" && -f "$mcp_json" ]]; then
            local name
            name=$(_run_plugin "$plugin" 'echo "$tool_name"')
            local result
            result=$(python3 -c "
import json
src = json.load(open('$mcp_json'))
merged = json.loads('$(echo "$merged" | sed "s/'/\\\\'/g")')
for k, v in src.get('mcpServers', {}).items():
    merged['mcpServers'][k] = v
print(json.dumps(merged))
" 2>/dev/null)
            if [[ -n "$result" ]]; then
                merged="$result"
                local count
                count=$(echo "$merged" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['mcpServers']))")
                ok "$name: 已合并 ($count 个 server)"
            fi
        fi
    done

    echo "$merged" | python3 -c "import json,sys; json.dump(json.load(sys.stdin), open('$MCP_SRC','w'), indent=2, ensure_ascii=False)"
    local total
    total=$(json_count "$MCP_SRC" "mcpServers")
    ok "合并完成: $total 个 MCP server → $MCP_SRC"
}

# ---- Rules 合并 ----
merge_rules() {
    local source_tool="$1"

    # 从 source 工具获取 rules 文件
    local rules_file=""
    for plugin in "${TOOL_PLUGINS[@]}"; do
        local name
        name=$(_run_plugin "$plugin" 'echo "$tool_name"')
        if [[ "$name" == "$source_tool" ]]; then
            rules_file=$(_run_plugin "$plugin" 'tool_get_rules_source' 2>/dev/null)
            break
        fi
    done

    if [[ -n "$rules_file" && -f "$rules_file" ]]; then
        cp "$rules_file" "$RULES_SRC"
        ok "从 $source_tool 复制规则文件 → $RULES_SRC"
    else
        # 使用默认模板
        cp "$AI_CONFIG_INSTALL_DIR/templates/rules.md" "$RULES_SRC"
        info "未找到已有规则文件，已创建默认模板 → $RULES_SRC"
    fi
}

# ---- 备份原始配置 ----
backup_original_configs() {
    for plugin in "${TOOL_PLUGINS[@]}"; do
        source "$plugin"
        local mcp_src
        mcp_src=$(_run_plugin "$plugin" 'tool_get_mcp_source' 2>/dev/null)
        if [[ -n "$mcp_src" && -f "$mcp_src" && ! -L "$mcp_src" ]]; then
            backup_file "$mcp_src"
        fi
        local rules_src
        rules_src=$(_run_plugin "$plugin" 'tool_get_rules_source' 2>/dev/null)
        if [[ -n "$rules_src" && -f "$rules_src" && ! -L "$rules_src" ]]; then
            backup_file "$rules_src"
        fi
    done
}
