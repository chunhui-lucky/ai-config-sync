# ai-config-sync

[中文文档](README.md) | **English**

> Unified configuration management for Codex, Cursor, and Claude Code. Edit once, sync everywhere.

## The Problem

When using multiple AI coding assistants, each tool maintains its own configuration:

- **MCP servers** in different formats (JSON / TOML / CLI) — adding one server means editing three places
- **Rules** scattered across `AGENTS.md`, `.cursorrules`, and `CLAUDE.md`
- **Configurations drift** over time, causing inconsistent behavior across tools

`ai-config-sync` solves this by maintaining a single source of truth and syncing to all tools automatically.

## Quick Start

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

### Initialize

Scan existing Codex / Cursor / Claude Code configs and merge into the unified repo:

```bash
ai-config init
```

Interactively choose a config source (defaults to Codex), then automatically:
1. Merge all MCP servers into `~/.config/ai-config/mcp.json`
2. Copy rules to `~/.config/ai-config/rules.md`
3. Back up original configs
4. Set up symlinks and run the first sync

### Daily Usage

```bash
# Edit configs (change once)
vim ~/.config/ai-config/mcp.json     # MCP servers
vim ~/.config/ai-config/rules.md     # AI rules

# Sync to all tools
ai-config sync

# Check status
ai-config status

# Start auto-watch (sync on file changes)
ai-config watch start
```

## Commands

| Command | Description |
|---------|-------------|
| `ai-config init [--source <tool>]` | Initialize unified config repo |
| `ai-config sync [mcp\|rules]` | Sync configs to all tools |
| `ai-config status` | Show sync status |
| `ai-config watch [start\|stop\|log]` | Manage auto-watch |
| `ai-config doctor` | Check environment health |

## Platform Support

| Platform | Symlinks | MCP Sync | Auto-Watch | Auto-Start |
|----------|----------|----------|------------|------------|
| **macOS** | `ln -sf` | TOML / symlink / CLI | fswatch | LaunchAgent |
| **Linux** | `ln -sf` | TOML / symlink / CLI | fswatch | Background process |
| **WSL** | `ln -sf` | TOML / symlink / CLI | fswatch | Background process |
| **Windows (Git Bash)** | `mklink /J` | TOML / junction / CLI | Python watchdog | Task Scheduler |
| **Windows (PowerShell)** | via Git Bash | via Git Bash | via Git Bash | Task Scheduler |

### Windows Prerequisites

- **Git for Windows** (includes Git Bash) — [download](https://git-scm.com/download/win)
- **Python 3** — [download](https://www.python.org/downloads/)
- **pip** (comes with Python 3) — used to install `watchdog` for file watching

The installer automatically installs `watchdog` on Windows and creates `.bat` / `.ps1` wrappers so `ai-config` works in both Git Bash and cmd.exe / PowerShell.

## Sync Mechanism

| Config | Codex | Cursor | Claude Code |
|--------|-------|--------|-------------|
| **Rules** | Symlink → `AGENTS.md` | Symlink → `.cursorrules` | Symlink → `CLAUDE.md` |
| **MCP** | TOML convert → `config.toml` | Symlink → `mcp.json` | CLI inject → `settings.json` |
| **Skills** | Use [skillshare](https://github.com/runkids/skillshare) |

- **Rules / Skills**: Symlinks — editing the file takes effect immediately (real-time)
- **MCP**: Codex and Claude Code need format conversion, handled automatically by `ai-config sync` or `ai-config watch start`

## Project-Level Config

In addition to global configs (`~/.codex/`, `~/.cursor/`, `~/.claude/`), each AI tool also supports project-level configs:

| Tool | Global Rules | Project-Level Rules |
|------|-------------|---------------------|
| Codex | `~/.codex/AGENTS.md` | `<project>/AGENTS.md` |
| Cursor | `~/.cursorrules` | `<project>/.cursorrules` |
| Claude Code | `~/.claude/CLAUDE.md` | `<project>/CLAUDE.md` |

Use `ai-config sync project` to sync unified rules to a specific project:

```bash
# Sync project-level config only
ai-config sync project --project /path/to/your/project

# Sync both global + project-level
ai-config sync all --project /path/to/your/project
```

This creates symlinks in the project directory so all AI tools use the same unified rules when working in that project.

## Config Repo Structure

```
~/.config/ai-config/
├── mcp.json     ← Unified MCP config (all MCP servers defined here)
└── rules.md     ← Unified rules (all AI rules defined here)
```

### mcp.json Format

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

Two MCP server types supported:
- **stdio**: `command` + `args` + `env`
- **HTTP/SSE**: `url` + `http_headers`

## AI Auto-Routing

During `init`, `ai-config` injects a **config maintenance rule** into `rules.md` that tells all AI assistants:

> When modifying MCP / Rules / Skills, always write to the unified config repo — not to tool-specific config files.

This means when you tell your AI assistant:

| What you say | What the AI does | Auto-sync? |
|-------------|-----------------|------------|
| "Add a rule: xxx" | Edit `~/.config/ai-config/rules.md` | Yes (symlink, instant) |
| "Add an MCP server: xxx" | Edit `~/.config/ai-config/mcp.json` + run sync | Yes (auto-distribute) |
| "Add a skill: xxx" | Create in `~/.config/skillshare/skills/` + run sync | Yes (auto-distribute) |

## Adding New AI Tools

Create a new file in `lib/tools/` (e.g., `windsurf.sh`) and implement the standard interface:

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

Submit a PR to add support for new tools!

## Auto-Watch

```bash
# Start (macOS: LaunchAgent; Linux: background; Windows: Task Scheduler)
ai-config watch start

# Stop
ai-config watch stop

# View logs
ai-config watch log
```

Requires:
- **macOS / Linux**: [fswatch](https://github.com/emcrisostomo/fswatch) (`brew install fswatch` or `apt install fswatch`)
- **Windows**: Python `watchdog` package (auto-installed by the installer, or `pip install watchdog`)

## Uninstall

```bash
# Stop watcher
ai-config watch stop

# Uninstall (keeps config data)
bash ~/.config/ai-config-sync/install.sh --uninstall
# Windows PowerShell:
# .\install.ps1 -Uninstall

# Full cleanup (including config data)
rm -rf ~/.config/ai-config/
```

## Works with skillshare

[skillshare](https://github.com/runkids/skillshare) focuses on Skills sync; `ai-config-sync` focuses on MCP and Rules. They complement each other:

```bash
# Install skillshare
npm install -g skillshare

# Initialize
skillshare init

# Add AI tool targets
skillshare target add codex ~/.codex/skills
skillshare target add cursor ~/.cursor/skills
skillshare target add claude-code ~/.claude/skills

# Sync skills
skillshare sync
```

`ai-config watch start` also monitors the skillshare skills directory and auto-syncs on changes.

## License

MIT
