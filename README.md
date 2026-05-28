# ai-config-sync

> 统一管理 Codex / Cursor / Claude Code 的 MCP、Rules、Skills 配置。改一处，三端生效。

## 痛点

使用多个 AI 编程工具时，每个工具各自维护一份配置：

- **MCP server** 格式不同（JSON / TOML / CLI），加一个要改三处
- **Rules** 分散在不同文件（`AGENTS.md` / `.cursorrules` / `CLAUDE.md`）
- 配置不同步时，工具行为不一致

`ai-config-sync` 让你在一个地方维护所有配置，自动同步到每个工具。

## 快速开始

### 安装

```bash
curl -fsSL https://raw.githubusercontent.com/chunhui-lucky/ai-config-sync/main/install.sh | bash
```

或手动安装：

```bash
git clone https://github.com/chunhui-lucky/ai-config-sync ~/.config/ai-config-sync
ln -sf ~/.config/ai-config-sync/bin/ai-config ~/.local/bin/ai-config
```

### 初始化

扫描已有的 Codex / Cursor / Claude Code 配置，合并到统一仓库：

```bash
ai-config init
```

交互式选择配置源（默认 Codex），自动完成：
1. 合并所有 MCP server 到 `~/.config/ai-config/mcp.json`
2. 复制规则到 `~/.config/ai-config/rules.md`
3. 备份原始配置
4. 建立符号链接 / 执行首次同步

### 日常使用

```bash
# 编辑配置（改一处）
vim ~/.config/ai-config/mcp.json     # 改 MCP
vim ~/.config/ai-config/rules.md     # 改规则

# 同步到所有工具
ai-config sync

# 查看状态
ai-config status

# 启动自动监听（文件变化时自动同步）
ai-config watch start
```

## 命令

| 命令 | 说明 |
|------|------|
| `ai-config init [--source <tool>]` | 初始化统一配置仓库 |
| `ai-config sync [mcp\|rules]` | 同步配置到所有工具 |
| `ai-config status` | 查看同步状态 |
| `ai-config watch [start\|stop\|log]` | 管理自动监听 |
| `ai-config doctor` | 检查环境健康状态 |

## 同步机制

| 配置项 | Codex | Cursor | Claude Code |
|--------|-------|--------|-------------|
| **Rules** | 符号链接 → `AGENTS.md` | 符号链接 → `.cursorrules` | 符号链接 → `CLAUDE.md` |
| **MCP** | TOML 转换写入 `config.toml` | 符号链接 → `mcp.json` | CLI 注入 `settings.json` |
| **Skills** | 推荐使用 [skillshare](https://github.com/runkids/skillshare) |

- **Rules / Skills**：通过符号链接，改文件即生效（实时）
- **MCP**：Codex 和 Claude Code 需要格式转换，`ai-config sync` 或 `ai-config watch start` 自动处理

## 配置仓库结构

```
~/.config/ai-config/
├── mcp.json     ← 统一 MCP 配置（所有工具的 MCP server 都定义在这里）
└── rules.md     ← 统一规则（所有工具的 AI rules 都定义在这里）
```

### mcp.json 格式

```json
{
  "mcpServers": {
    "gitlab-mcp": {
      "command": "/opt/homebrew/bin/node",
      "args": ["/path/to/mcp-gitlab/index.js"],
      "env": {
        "GITLAB_PERSONAL_ACCESS_TOKEN": "your-token",
        "GITLAB_API_URL": "https://gitlab.com/api/v4"
      }
    },
    "log-mcp": {
      "url": "https://your-log-service/mcp",
      "http_headers": {
        "Authorization": "Bearer your-token"
      }
    }
  }
}
```

支持两种 MCP server 类型：
- **stdio**：`command` + `args` + `env`
- **HTTP/SSE**：`url` + `http_headers`

## 添加新的 AI 工具

在 `lib/tools/` 目录下创建一个新文件（如 `windsurf.sh`），实现标准接口：

```bash
#!/usr/bin/env bash
tool_name="windsurf"

tool_detect() {
    [[ -d "$HOME/.windsurf" ]]
}

tool_sync_mcp() {
    local mcp_src="$1"
    safe_symlink "$mcp_src" "$HOME/.windsurf/mcp.json" "mcp.json"
}

tool_sync_rules() {
    local rules_src="$1"
    safe_symlink "$rules_src" "$HOME/.windsurfrules" ".windsurfrules"
}

tool_status_mcp() {
    check_link_status "$HOME/.windsurf/mcp.json" "$MCP_SRC"
}

tool_status_rules() {
    check_link_status "$HOME/.windsurfrules" "$RULES_SRC"
}

tool_get_mcp_source() {
    [[ -f "$HOME/.windsurf/mcp.json" && ! -L "$HOME/.windsurf/mcp.json" ]] && echo "$HOME/.windsurf/mcp.json"
}

tool_get_rules_source() {
    [[ -f "$HOME/.windsurfrules" && ! -L "$HOME/.windsurfrules" ]] && echo "$HOME/.windsurfrules"
}
```

提交 PR 即可支持新工具！

## 自动监听

```bash
# 启动（macOS 使用 LaunchAgent，开机自启；Linux 使用后台进程）
ai-config watch start

# 停止
ai-config watch stop

# 查看日志
ai-config watch log
```

需要安装 [fswatch](https://github.com/emcrisostomo/fswatch)：

```bash
# macOS
brew install fswatch

# Ubuntu/Debian
sudo apt install fswatch

# Fedora
sudo yum install fswatch
```

## 卸载

```bash
# 停止监听
ai-config watch stop

# 卸载工具（保留配置数据）
bash ~/.config/ai-config-sync/install.sh --uninstall

# 完全清除（包括配置数据）
rm -rf ~/.config/ai-config/
```

## 与 skillshare 配合

[skillshare](https://github.com/runkids/skillshare) 专注于 Skills 同步，`ai-config-sync` 专注于 MCP 和 Rules。两者互补：

```bash
# 安装 skillshare
npm install -g skillshare

# 初始化 skillshare
skillshare init

# 添加 AI 工具目标
skillshare target add codex ~/.codex/skills
skillshare target add cursor ~/.cursor/skills
skillshare target add claude-code ~/.claude/skills

# 同步 skills
skillshare sync
```

`ai-config watch start` 会同时监听 skillshare 的 skills 目录变化并自动同步。

## 许可证

MIT
