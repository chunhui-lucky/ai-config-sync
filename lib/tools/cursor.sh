#!/usr/bin/env bash
# ============================================================
# Cursor 工具插件
# ============================================================
tool_name="cursor"
CURSOR_DIR="$HOME/.cursor"
CURSOR_MCP="$CURSOR_DIR/mcp.json"
CURSOR_RULES="$HOME/.cursorrules"

tool_detect() {
    [[ -d "$CURSOR_DIR" ]]
}

tool_sync_mcp() {
    local mcp_src="$1"
    safe_symlink "$mcp_src" "$CURSOR_MCP" "mcp.json"
}

tool_sync_rules() {
    local rules_src="$1"
    safe_symlink "$rules_src" "$CURSOR_RULES" ".cursorrules"
}

tool_status_mcp() {
    check_link_status "$CURSOR_MCP" "$MCP_SRC"
}

tool_status_rules() {
    check_link_status "$CURSOR_RULES" "$RULES_SRC"
}

tool_get_mcp_source() {
    if [[ -f "$CURSOR_MCP" && ! -L "$CURSOR_MCP" ]]; then
        echo "$CURSOR_MCP"
    fi
}

tool_get_rules_source() {
    if [[ -f "$CURSOR_RULES" && ! -L "$CURSOR_RULES" ]]; then
        echo "$CURSOR_RULES"
    fi
}
