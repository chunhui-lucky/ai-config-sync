# ai-config-sync

**中文文档** | [English](README_EN.md)

> 统一管理 Codex / Cursor / Claude Code 的 MCP、Rules、Skills 配置。改一处，三端生效。

## 为什么需要它

同时使用多个 AI 编程工具时，每个工具各自维护一份配置：

- **MCP server** 格式不同（JSON / TOML / CLI），加一个要改三处
- **Rules** 分散在 `AGENTS.md` / `.cursorrules` / `CLAUDE.md` 三个文件
- 配置不同步 → 工具行为不一致

`ai-config-sync` 让你在一个地方维护所有配置，自动同步到每个工具。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/chunhui-lucky/ai-config-sync/main/install.sh | bash
```

> 支持 macOS / Linux / Windows (Git Bash)，安装器会自动检测平台并处理依赖。

## 初始化

```bash
ai-config init
```

它会扫描你已有的 Codex / Cursor / Claude Code 配置，交互式选择配置源，然后自动完成：

1. 合并所有 MCP server → `~/.config/ai-config/mcp.json`
2. 复制规则 → `~/.config/ai-config/rules.md`
3. 备份原始配置
4. 建立符号链接 + 执行首次同步

**init 之后，所有配置只需在 `~/.config/ai-config/` 下维护。**

## 日常使用

```bash
# 改配置（只改这一处）
vim ~/.config/ai-config/mcp.json     # 改 MCP server
vim ~/.config/ai-config/rules.md     # 改 AI 规则

# 同步到所有工具
ai-config sync

# 查看状态
ai-config status
```

**改 Rules 后不需要 sync**（符号链接，改完即时生效）。只有改 MCP 后需要跑 `ai-config sync`，因为 Codex 和 Claude Code 的 MCP 配置格式不同，需要转换。

> 💡 开启自动监听后，改 MCP 也不用手动 sync 了：`ai-config watch start`

## AI 自动路由

初始化时，`ai-config` 会在 `rules.md` 中自动注入一段配置维护规则，告诉 AI：

> 修改 MCP / Rules / Skills 时，必须写入统一配置仓库，不要直接改各工具的配置文件。

这样你直接跟 AI 说就行：

| 你说的话 | AI 的行为 | 你需要做 |
|---------|----------|---------|
| "加一条 rule：xxx" | 编辑 `rules.md` | 什么都不用做，即时生效 |
| "加一个 MCP：xxx" | 编辑 `mcp.json` | `ai-config sync`（或开着 watch 自动） |
| "加一个 skill：xxx" | 创建在 `skillshare/skills/` | `skillshare sync` |

## 命令参考

| 命令 | 说明 |
|------|------|
| `ai-config init [--source codex\|cursor\|claude-code]` | 初始化（扫描已有配置并合并） |
| `ai-config sync [mcp\|rules\|project\|all]` | 同步到所有工具（默认 all） |
| `ai-config sync project --project <path>` | 同步项目级配置到指定项目 |
| `ai-config status` | 查看同步状态 |
| `ai-config watch start` | 启动自动监听（文件变化时自动同步） |
| `ai-config watch stop` | 停止自动监听 |
| `ai-config watch log` | 查看监听日志 |
| `ai-config doctor` | 检查环境健康状态 |

## 配置格式

### mcp.json

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

### rules.md

普通 Markdown 文件，内容就是你想让所有 AI 工具遵循的规则。支持任意格式，`init` 时会从你现有的规则文件中导入。

---

## 工作原理

以下内容面向想了解实现细节的用户和贡献者。

### 同步机制

| 配置项 | Codex | Cursor | Claude Code |
|--------|-------|--------|-------------|
| **Rules** | 符号链接 → `AGENTS.md` | 符号链接 → `.cursorrules` | 符号链接 → `CLAUDE.md` |
| **MCP** | JSON→TOML 转换写入 `config.toml` | 符号链接 → `mcp.json` | CLI `add-json` 注入 `settings.json` |
| **Skills** | 推荐 [skillshare](https://github.com/runkids/skillshare) |

- **Rules** 通过符号链接，三个工具读取同一个文件，改即生效
- **MCP** 因格式差异无法统一符号链接：Cursor 支持标准 JSON 所以直接链接；Codex 用 TOML 格式，`sync` 时通过 `_mcp_to_toml.py` 转换；Claude Code 只能通过 CLI 管理，`sync` 时通过 `claude mcp add-json` 注入
- **Skills** 不在本工具范围内，推荐使用 skillshare（`watch` 会自动联动）

### 平台支持

| 平台 | 符号链接 | 自动监听 | 开机自启 |
|------|---------|----------|---------|
| **macOS** | `ln -sf` | fswatch | LaunchAgent |
| **Linux** | `ln -sf` | fswatch | 后台进程 |
| **WSL** | `ln -sf` | fswatch | 后台进程 |
| **Windows (Git Bash)** | junction | Python watchdog | Task Scheduler |

Windows 前置依赖：[Git for Windows](https://git-scm.com/download/win) + [Python 3](https://www.python.org/downloads/)。安装器会自动安装 watchdog 并创建 `.bat` 包装脚本。

### 项目级配置

每个 AI 工具除了全局配置，还支持项目级配置（`<project>/AGENTS.md`、`.cursorrules`、`CLAUDE.md`）。

```bash
ai-config sync project --project /path/to/your/project
```

会在项目目录下创建符号链接，指向统一的 `rules.md`。

### 与 skillshare 配合

[skillshare](https://github.com/runkids/skillshare) 负责 Skills 同步，`ai-config-sync` 负责 MCP 和 Rules，互补关系。`ai-config watch start` 会自动联动 skillshare 的 skills 目录变化。

## 贡献指南：添加新的 AI 工具

在 `lib/tools/` 下创建新文件（如 `windsurf.sh`），实现标准接口：

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

tool_status_mcp()    { check_link_status "$HOME/.windsurf/mcp.json" "$MCP_SRC"; }
tool_status_rules()  { check_link_status "$HOME/.windsurfrules" "$RULES_SRC"; }
tool_get_mcp_source()    { [[ -f "$HOME/.windsurf/mcp.json" && ! -L "$HOME/.windsurf/mcp.json" ]] && echo "$HOME/.windsurf/mcp.json"; }
tool_get_rules_source()  { [[ -f "$HOME/.windsurfrules" && ! -L "$HOME/.windsurfrules" ]] && echo "$HOME/.windsurfrules"; }
```

提交 PR 即可！

## 卸载

```bash
ai-config watch stop
bash ~/.config/ai-config-sync/install.sh --uninstall

# 完全清除（包括配置数据）
rm -rf ~/.config/ai-config/
```

## License

MIT
