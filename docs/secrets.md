# Secrets

Credentials live in one env file on the box, `/var/lib/devbox/secrets.env`
(option `devbox.secretsFile`), never in git. Nothing secret is needed to build
or boot.

```sh
sudo scripts/secrets-file-init.sh
```

prompts for each value, writes the file and restarts opencode. Every value is
optional:

| variable | used by |
| --- | --- |
| `OPENCODE_SERVER_PASSWORD` | basic auth on the web UI and API. Set it: without one, opencode invents a new password at every start, which logs every browser out |
| `GITEA_HOST`, `GITEA_TOKEN` | the `gitea` MCP server |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | the `github` MCP server. Use a read-only token: the server is started with `--read-only` |
| `OPENROUTER_API_KEY` | a model provider, if you don't log in to one in the web UI |

How the file is used:

- **Mode `0640 root:users`.** The operator account can read it, because the
  MCP launchers (`devbox-mcp-gitea`, `devbox-mcp-github`) run as that account,
  under opencode or from an SSH shell. That costs nothing: the same account
  has passwordless sudo.
- **The launchers read it when they start.** No token appears in
  `opencode.json`, `~/.claude.json` or agy's config.
- **opencode reads it with `EnvironmentFile=-…`**: a missing file is not an
  error, the box just has no credentials. A changed value needs
  `sudo systemctl restart opencode` (and a restart of any running `claude` or
  `agy`), not a rebuild.
- **The format is plain `KEY=value` lines.** Quotes around a value are
  stripped; nothing is expanded.

## Without a Gitea server

The `gitea` MCP server is always configured. With no `GITEA_HOST`, `gitea-mcp`
falls back to the public **gitea.com**, without logging in: its tools still
work, against public data there. To drop the server entirely, remove `gitea`
from `devbox.mcpServers` in `modules/mcp.nix`. Every agent on the box takes
its servers from that one list.

Why one file rather than sops or agenix: see
[decisions.md](decisions.md#secrets-one-optional-env-file).
