#!/usr/bin/env python3
"""
_toml_to_json.py — 从 Codex config.toml 中提取 MCP servers 并输出 JSON 格式。

用法: python3 _toml_to_json.py <config.toml>
输出: JSON 到 stdout，格式同 mcp.json
"""
import re
import json
import sys


def parse_mcp_servers(toml_content: str) -> dict:
    """从 TOML 内容中提取 [mcp_servers.*] 段落，转换为 dict。"""
    servers = {}
    current_server = None
    current_section = None  # None, "env", "http_headers"

    for line in toml_content.split("\n"):
        stripped = line.strip()

        # 匹配 [mcp_servers.NAME] 或 [mcp_servers.NAME.subsection]
        match = re.match(r"^\[mcp_servers\.([^\]]+)\]$", stripped)
        if match:
            parts = match.group(1).split(".")
            if len(parts) == 1:
                current_server = parts[0]
                current_section = None
                servers[current_server] = {}
            elif len(parts) == 2:
                current_section = parts[1]
                if current_server and current_section not in ("env", "http_headers"):
                    current_section = None
            continue

        # 遇到其他 section 头，停止解析
        if stripped.startswith("[") and not stripped.startswith("[mcp_servers."):
            current_server = None
            current_section = None
            continue

        if not current_server:
            continue

        # 解析 key = value
        kv_match = re.match(r'^(\w+)\s*=\s*"([^"]*)"$', stripped)
        if kv_match:
            key, value = kv_match.group(1), kv_match.group(2)
            if current_section:
                servers[current_server].setdefault(current_section, {})[key] = value
            else:
                servers[current_server][key] = value
            continue

        # 解析 key = [...] (args)
        args_match = re.match(r"^(\w+)\s*=\s*\[(.*)\]$", stripped)
        if args_match:
            key = args_match.group(1)
            values_str = args_match.group(2)
            values = re.findall(r'"([^"]*)"', values_str)
            if current_section:
                servers[current_server].setdefault(current_section, {})[key] = values
            else:
                servers[current_server][key] = values
            continue

        # 解析 key = number
        num_match = re.match(r"^(\w+)\s*=\s*(\d+)$", stripped)
        if num_match:
            key, value = num_match.group(1), int(num_match.group(2))
            if current_section:
                servers[current_server].setdefault(current_section, {})[key] = value
            else:
                servers[current_server][key] = value
            continue

    return servers


def main():
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <config.toml>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        content = f.read()

    servers = parse_mcp_servers(content)
    result = {"mcpServers": servers}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
