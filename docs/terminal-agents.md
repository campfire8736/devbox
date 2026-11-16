# Terminal agents: Claude Code and the Antigravity CLI (agy)

Enabled in the host file (`devbox.claudeCode.enable`,
`devbox.antigravity.enable`); set either to `false` to leave it out. Both are unfree; the flake allows exactly these
two by name. They come from `nixpkgs-unstable`, like opencode, and do not
self-update (the store is read-only; nixpkgs' `claude` sets
`DISABLE_AUTOUPDATER`).

```sh
ssh dev@devbox -t tmux new -A -s main
cd /srv/work/<name>/<name>
claude        # or: agy
```

The first start asks you to log in. Over SSH both print a URL to open on your
own machine (Claude: Claude account or `ANTHROPIC_API_KEY`; agy: Google
account).

What each one gets:

| | Claude Code | agy |
| --- | --- | --- |
| MCP servers (gitea, github, serena) | `claude mcp add-json --scope user` | `agy mcp add` |
| instructions | `~/.claude/CLAUDE.md` imports `/etc/devbox/agents/claude.md` | `~/.gemini/AGENTS.md` → `/etc/devbox/agents/agy.md` |
| project environment | a `SessionStart`/`CwdChanged` hook (`/etc/claude-code/managed-settings.json`) loads it whenever the directory changes | the `agy` wrapper starts the CLI in the environment of the launch directory |

- **MCP servers** are registered by `devbox-agents-sync.service`, at boot and
  whenever a rebuild changes the server set, through each tool's own CLI. Both
  tools also write those files themselves, so the repo does not own them:
  servers you add are kept, and a devbox server you remove comes back on the
  next run. Restart a running `claude`/`agy` to pick up a change.
- **Tokens** never appear in those configs. Each server is a launcher
  (`devbox-mcp-gitea`, `devbox-mcp-github`) that reads the secrets file when
  it starts, so it works the same under opencode or from an SSH shell. opencode
  uses the same launchers.
- **`~/.claude/CLAUDE.md`** is created once with the import line and is then
  yours (Claude Code's `/memory` edits it). If you already had one, add
  `@/etc/devbox/agents/claude.md` to it yourself; `devbox-doctor` checks.
- **Environment, Claude Code:** its working directory persists between
  commands, and the hook writes the new directory's environment (same rules as
  `agent-shell`) to `CLAUDE_ENV_FILE`, which Claude Code applies before each
  later command. It takes effect from the command *after* a `cd`.
- **Environment, agy:** it has no hook or shell setting, so its commands
  inherit the environment it was started in. Start one `agy` per project, from
  that project's folder; `agent-shell -c '…'` covers the odd command elsewhere.
