#!/usr/bin/env bash
# ============================================================
# Codex 工具插件
# ============================================================
tool_name="codex"
CODEX_DIR="$HOME/.codex"
CODEX_CONFIG="$CODEX_DIR/config.toml"
CODEX_AGENTS="$CODEX_DIR/AGENTS.md"

tool_detect() {
    [[ -d "$CODEX_DIR" ]]
}

tool_sync_mcp() {
    local mcp_src="$1"
    if [[ ! -f "$CODEX_CONFIG" ]]; then
        warn "Codex config.toml 不存在，跳过 MCP 同步"
        return 1
    fi
    backup_file "$CODEX_CONFIG"
    python3 "$AI_CONFIG_INSTALL_DIR/lib/_mcp_to_toml.py" "$mcp_src" "$CODEX_CONFIG"
    ok "config.toml [mcp_servers] 已更新"
}

tool_sync_rules() {
    local rules_src="$1"
    safe_symlink "$rules_src" "$CODEX_AGENTS" "AGENTS.md"
}

tool_status_mcp() {
    if [[ -f "$CODEX_CONFIG" ]]; then
        local count
        count=$(grep -c '^\[mcp_servers\.' "$CODEX_CONFIG" 2>/dev/null || echo 0)
        echo "通过 sync.sh 同步 ($count 个 server，TOML 嵌入 config.toml)"
    else
        echo "config.toml 不存在"
    fi
}

tool_status_rules() {
    check_link_status "$CODEX_AGENTS" "$RULES_SRC"
}

tool_get_mcp_source() {
    if [[ -f "$CODEX_CONFIG" ]]; then
        python3 "$AI_CONFIG_INSTALL_DIR/lib/_toml_to_json.py" "$CODEX_CONFIG" 2>/dev/null
    fi
}

tool_get_rules_source() {
    if [[ -f "$CODEX_AGENTS" && ! -L "$CODEX_AGENTS" ]]; then
        echo "$CODEX_AGENTS"
    fi
}
