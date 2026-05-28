# ai-config-sync

[中文文档](README.md) | **English**

> Unified configuration management for Codex, Cursor, and Claude Code. Edit once, sync everywhere.

## Why

When using multiple AI coding assistants, each tool maintains its own configuration:

- **MCP servers** in different formats (JSON / TOML / CLI) — adding one means editing three places
- **Rules** scattered across `AGENTS.md`, `.cursorrules`, and `CLAUDE.md`
- **Config drift** — tools behave differently over time

`ai-config-sync` gives you a single source of truth that syncs to every tool automatically.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/chunhui-lucky/ai-config-sync/main/install.sh | bash
```

> Supports macOS / Linux / Windows (Git Bash). The installer auto-detects your platform and handles dependencies.

## Initialize

```bash
ai-config init
```

It scans your existing Codex / Cursor / Claude Code configs, lets you pick a source of truth interactively, then automatically:

1. Merges all MCP servers → `~/.config/ai-config/mcp.json`
2. Copies rules → `~/.config/ai-config/rules.md`
3. Backs up original configs
4. Creates symlinks + runs the first sync

**After init, all configs are maintained in `~/.config/ai-config/` only.**

## Daily Usage

```bash
# Edit configs (change once)
vim ~/.config/ai-config/mcp.json     # MCP servers
vim ~/.config/ai-config/rules.md     # AI rules

# Sync to all tools
ai-config sync

# Check status
ai-config status
```

**Rule changes don't need sync** — they're symlinked and take effect instantly. Only MCP changes require `ai-config sync`, because Codex and Claude Code use different config formats that need conversion.

> 💡 With auto-watch enabled (`ai-config watch start`), even MCP changes sync automatically.

## AI Auto-Routing

During `init`, `ai-config` injects a **config maintenance rule** into `rules.md` that tells all AI assistants:

> When modifying MCP / Rules / Skills, always write to the unified config repo — not to tool-specific config files.

So you can just tell your AI assistant:

| What you say | What the AI does | What you need to do |
|-------------|-----------------|---------------------|
| "Add a rule: xxx" | Edits `rules.md` | Nothing — instant effect |
| "Add an MCP: xxx" | Edits `mcp.json` | `ai-config sync` (or auto with watch) |
| "Add a skill: xxx" | Creates in `skillshare/skills/` | `skillshare sync` |

## Command Reference

| Command | Description |
|---------|-------------|
| `ai-config init [--source codex\|cursor\|claude-code]` | Initialize (scan & merge existing configs) |
| `ai-config sync [mcp\|rules\|project\|all]` | Sync to all tools (default: all) |
| `ai-config sync project --project <path>` | Sync project-level config |
| `ai-config status` | Show sync status |
| `ai-config watch start` | Start file watcher (auto-sync on changes) |
| `ai-config watch stop` | Stop file watcher |
| `ai-config watch log` | Show watcher logs |
| `ai-config doctor` | Check environment health |

## Config Format

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

Two MCP server types supported:
- **stdio**: `command` + `args` + `env`
- **HTTP/SSE**: `url` + `http_headers`

### rules.md

A plain Markdown file containing the rules you want all AI tools to follow. Any format works — content is imported from your existing rules file during `init`.

---

## How It Works

The following is for users who want to understand the implementation details.

### Sync Mechanism

| Config | Codex | Cursor | Claude Code |
|--------|-------|--------|-------------|
| **Rules** | Symlink → `AGENTS.md` | Symlink → `.cursorrules` | Symlink → `CLAUDE.md` |
| **MCP** | JSON→TOML convert → `config.toml` | Symlink → `mcp.json` | CLI `add-json` → `settings.json` |
| **Skills** | Use [skillshare](https://github.com/runkids/skillshare) |

- **Rules** are symlinked — all tools read the same file, changes take effect instantly
- **MCP** can't be uniformly symlinked due to format differences: Cursor supports standard JSON (direct link); Codex uses TOML (converted via `_mcp_to_toml.py` on sync); Claude Code only accepts CLI injection (`claude mcp add-json`)
- **Skills** are out of scope — use [skillshare](https://github.com/runkids/skillshare) (auto-linked by `watch`)

### Platform Support

| Platform | Symlinks | Auto-Watch | Auto-Start |
|----------|----------|------------|------------|
| **macOS** | `ln -sf` | fswatch | LaunchAgent |
| **Linux** | `ln -sf` | fswatch | Background process |
| **WSL** | `ln -sf` | fswatch | Background process |
| **Windows (Git Bash)** | junction | Python watchdog | Task Scheduler |

Windows prerequisites: [Git for Windows](https://git-scm.com/download/win) + [Python 3](https://www.python.org/downloads/). The installer auto-installs watchdog and creates `.bat` wrappers.

### Project-Level Config

Each AI tool also supports project-level configs (`<project>/AGENTS.md`, `.cursorrules`, `CLAUDE.md`).

```bash
ai-config sync project --project /path/to/your/project
```

Creates symlinks in the project directory pointing to the unified `rules.md`.

### Works with skillshare

[skillshare](https://github.com/runkids/skillshare) handles Skills sync; `ai-config-sync` handles MCP and Rules. Complementary tools — `ai-config watch start` auto-links skillshare's skills directory changes.

## Contributing: Adding New AI Tools

Create a new file in `lib/tools/` (e.g., `windsurf.sh`) implementing the standard interface:

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

Submit a PR!

## Uninstall

```bash
ai-config watch stop
bash ~/.config/ai-config-sync/install.sh --uninstall

# Full cleanup (including config data)
rm -rf ~/.config/ai-config/
```

## License

MIT
