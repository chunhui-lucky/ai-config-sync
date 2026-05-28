#!/usr/bin/env python3
"""
_mcp_to_toml.py — 将 mcp.json 转换为 TOML 格式，更新 Codex 的 config.toml 中 [mcp_servers] 部分。

用法: python3 _mcp_to_toml.py <mcp.json> <config.toml>
"""
import json
import re
import sys


def json_to_toml_block(name: str, config: dict) -> str:
    """将一个 MCP server 配置转换为 TOML 段落。"""
    lines = [f"[mcp_servers.{name}]"]

    # type 字段
    if "type" in config:
        lines.append(f'type = "{config["type"]}"')

    # url 类型 (streamable HTTP / SSE)
    if "url" in config:
        lines.append(f'url = "{config["url"]}"')
        if "http_headers" in config:
            lines.append(f"\n[mcp_servers.{name}.http_headers]")
            for hk, hv in config["http_headers"].items():
                lines.append(f'{hk} = "{hv}"')
        return "\n".join(lines) + "\n"

    # command/args 类型 (stdio)
    if "command" in config:
        lines.append(f'command = "{config["command"]}"')

    if "args" in config:
        args = ", ".join(f'"{a}"' for a in config["args"])
        lines.append(f"args = [{args}]")

    # 标量字段
    for key in ("startup_timeout_sec",):
        if key in config:
            lines.append(f"{key} = {config[key]}")

    # env 子段
    if "env" in config:
        lines.append(f"\n[mcp_servers.{name}.env]")
        for ek, ev in sorted(config["env"].items()):
            escaped = str(ev).replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'{ek} = "{escaped}"')

    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) != 3:
        print(f"用法: {sys.argv[0]} <mcp.json> <config.toml>", file=sys.stderr)
        sys.exit(1)

    mcp_json_path = sys.argv[1]
    config_toml_path = sys.argv[2]

    with open(mcp_json_path) as f:
        mcp_data = json.load(f)

    servers = mcp_data.get("mcpServers", {})

    # 生成所有 MCP server 的 TOML 段落
    toml_blocks = []
    for name, config in sorted(servers.items()):
        toml_blocks.append(json_to_toml_block(name, config))

    new_mcp_section = "\n".join(toml_blocks)

    # 读取 config.toml
    with open(config_toml_path) as f:
        content = f.read()

    # 删除所有现有的 [mcp_servers.*] 段落
    lines = content.split("\n")
    result_lines = []
    in_mcp_section = False

    for line in lines:
        stripped = line.strip()
        if re.match(r"^\[mcp_servers\.", stripped):
            in_mcp_section = True
            continue
        if in_mcp_section and re.match(r"^\[", stripped) and not stripped.startswith("[mcp_servers."):
            in_mcp_section = False
        if in_mcp_section:
            continue
        result_lines.append(line)

    # 找到插入位置：在开头的标量配置之后、其他 section 之前
    insert_idx = 0
    for i, line in enumerate(result_lines):
        stripped = line.strip()
        if stripped and not stripped.startswith("["):
            insert_idx = i + 1
            continue
        if stripped.startswith("["):
            insert_idx = i
            break

    before = result_lines[:insert_idx]
    after = result_lines[insert_idx:]

    while before and before[-1].strip() == "":
        before.pop()
    while after and after[0].strip() == "":
        after.pop(0)

    new_content = "\n".join(before) + "\n\n" + new_mcp_section + "\n" + "\n".join(after)

    with open(config_toml_path, "w") as f:
        f.write(new_content)


if __name__ == "__main__":
    main()
