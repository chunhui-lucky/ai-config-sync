#!/usr/bin/env bash
# ============================================================
# Claude Code 工具插件
# ============================================================
tool_name="claude-code"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_RULES="$CLAUDE_DIR/CLAUDE.md"

tool_detect() {
    command -v claude &>/dev/null
}

tool_sync_mcp() {
    local mcp_src="$1"
    if ! command -v claude &>/dev/null; then
        warn "claude CLI 未安装，跳过 MCP 同步"
        return 1
    fi

    local names
    names=$(python3 -c "import json; [print(n) for n in json.load(open('$mcp_src'))['mcpServers']]" 2>/dev/null)
    local count=0
    for name in $names; do
        # Claude Code 格式转换：url 类型加 type:sse，http_headers → headers
        local cfg
        cfg=$(python3 -c "
import json
c = json.load(open('$mcp_src'))['mcpServers']['$name']
if 'url' in c and 'type' not in c:
    c['type'] = 'sse'
if 'http_headers' in c:
    c['headers'] = c.pop('http_headers')
print(json.dumps(c))
")
        # 先移除已存在的（忽略错误），再添加
        claude mcp remove "$name" --scope user 2>/dev/null || true
        if claude mcp add-json "$name" "$cfg" --scope user 2>/dev/null; then
            ok "$name"
            ((count++))
        else
            warn "$name (添加失败)"
        fi
    done
    ok "共添加 $count 个 MCP server"
}

tool_sync_rules() {
    local rules_src="$1"
    safe_symlink "$rules_src" "$CLAUDE_RULES" "CLAUDE.md"
}

tool_status_mcp() {
    if command -v claude &>/dev/null; then
        echo "通过 sync.sh 同步 (CLI 注入 settings.json)"
    else
        echo "claude CLI 未安装"
    fi
}

tool_status_rules() {
    check_link_status "$CLAUDE_RULES" "$RULES_SRC"
}

tool_get_mcp_source() {
    # Claude Code MCP 通过 CLI 管理，不直接读取文件
    # 返回空表示无法作为 MCP 源
    echo ""
}

tool_get_rules_source() {
    if [[ -f "$CLAUDE_RULES" && ! -L "$CLAUDE_RULES" ]]; then
        echo "$CLAUDE_RULES"
    fi
}

# 项目级配置
tool_sync_project_rules() {
    local project_path="$1"
    local rules_src="$2"
    local project_rules="$project_path/CLAUDE.md"
    safe_symlink "$rules_src" "$project_rules" "CLAUDE.md (project)"
}

tool_status_project() {
    local project_path="$1"
    local project_rules="$project_path/CLAUDE.md"
    check_link_status "$project_rules" "$RULES_SRC"
}
