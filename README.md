# ai-config-sync

**中文文档** | [English](README_EN.md)

> 统一管理 Codex / Cursor / Claude Code 的 MCP、Rules、Skills 配置。改一处，三端生效。

## 痛点

使用多个 AI 编程工具时，每个工具各自维护一份配置：

- **MCP server** 格式不同（JSON / TOML / CLI），加一个要改三处
- **Rules** 分散在不同文件（`AGENTS.md` / `.cursorrules` / `CLAUDE.md`）
- 配置不同步时，工具行为不一致

`ai-config-sync` 让你在一个地方维护所有配置，自动同步到每个工具。

## 快速开始

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/chunhui-lucky/ai-config-sync/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/chunhui-lucky/ai-config-sync/main/install.ps1 | iex
```

### Windows (Git Bash)

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

## 平台支持

| 平台 | 符号链接 | MCP 同步 | 自动监听 | 开机自启 |
|------|---------|----------|---------|---------|
| **macOS** | `ln -sf` | TOML / symlink / CLI | fswatch | LaunchAgent |
| **Linux** | `ln -sf` | TOML / symlink / CLI | fswatch | 后台进程 |
| **WSL** | `ln -sf` | TOML / symlink / CLI | fswatch | 后台进程 |
| **Windows (Git Bash)** | `mklink /J` | TOML / junction / CLI | Python watchdog | Task Scheduler |
| **Windows (PowerShell)** | 通过 Git Bash | 通过 Git Bash | 通过 Git Bash | Task Scheduler |

### Windows 前置依赖

- **Git for Windows**（包含 Git Bash）— [下载](https://git-scm.com/download/win)
- **Python 3** — [下载](https://www.python.org/downloads/)
- **pip**（Python 3 自带）— 用于安装 `watchdog` 文件监听库

安装器会自动安装 `watchdog`，并创建 `.bat` / `.ps1` 包装脚本，使 `ai-config` 在 Git Bash 和 cmd.exe / PowerShell 中都能使用。

## 同步机制

| 配置项 | Codex | Cursor | Claude Code |
|--------|-------|--------|-------------|
| **Rules** | 符号链接 → `AGENTS.md` | 符号链接 → `.cursorrules` | 符号链接 → `CLAUDE.md` |
| **MCP** | TOML 转换写入 `config.toml` | 符号链接 → `mcp.json` | CLI 注入 `settings.json` |
| **Skills** | 推荐使用 [skillshare](https://github.com/runkids/skillshare) |

- **Rules / Skills**：通过符号链接，改文件即生效（实时）
- **MCP**：Codex 和 Claude Code 需要格式转换，`ai-config sync` 或 `ai-config watch start` 自动处理

## 项目级配置

除了全局配置（`~/.codex/`, `~/.cursor/`, `~/.claude/`），每个 AI 工具还支持项目级配置：

| 工具 | 全局 Rules | 项目级 Rules |
|------|-----------|-------------|
| Codex | `~/.codex/AGENTS.md` | `<project>/AGENTS.md` |
| Cursor | `~/.cursorrules` | `<project>/.cursorrules` |
| Claude Code | `~/.claude/CLAUDE.md` | `<project>/CLAUDE.md` |

使用 `ai-config sync project` 可以将统一规则同步到指定项目：

```bash
# 同步项目级配置
ai-config sync project --project /path/to/your/project

# 同时同步全局 + 项目级
ai-config sync all --project /path/to/your/project
```

这会在项目目录下创建符号链接，让所有 AI 工具在该项目中使用统一的规则。

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

## AI 自动路由

初始化时，`ai-config init` 会在 `rules.md` 中自动注入一段**配置维护规则**，告诉所有 AI 编程助手：

> 修改 MCP / Rules / Skills 时，必须写入统一配置仓库，而不是各工具自己的配置文件。

这样当你在 Codex / Cursor / Claude Code 中对 AI 说：

| 你说的话 | AI 的正确行为 | 是否自动同步 |
|---------|------------|------------|
| "加一条 rule：xxx" | 编辑 `~/.config/ai-config/rules.md` | ✅ 符号链接，即时生效 |
| "加一个 MCP server：xxx" | 编辑 `~/.config/ai-config/mcp.json` + 运行 `ai-config sync mcp` | ✅ 自动分发 |
| "加一个 skill：xxx" | 在 `~/.config/skillshare/skills/` 创建 + 运行 `skillshare sync` | ✅ 自动分发 |

这段规则在 `init` 时自动注入，你不需要手动维护。如果你想自定义，可以直接编辑 `rules.md` 中的「配置维护」段落。

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
# 启动（macOS: LaunchAgent, Linux: 后台进程, Windows: Task Scheduler）
ai-config watch start

# 停止
ai-config watch stop

# 查看日志
ai-config watch log
```

需要安装文件监听工具：

```bash
# macOS
brew install fswatch

# Ubuntu/Debian
sudo apt install fswatch

# Fedora
sudo yum install fswatch

# Windows (自动安装，或手动)
pip install watchdog
```

## 卸载

```bash
# 停止监听
ai-config watch stop

# 卸载工具（保留配置数据）
# macOS / Linux / Windows Git Bash:
bash ~/.config/ai-config-sync/install.sh --uninstall

# Windows PowerShell:
# .\install.ps1 -Uninstall

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
