# Security

## Threat model

devbox gives AI agents a machine to do what they want with. The design
assumes the agents can and will run arbitrary commands, so the protections sit
around the VM, not inside it.

- **The VM is the boundary.** The operator account, which the agents use, has
  passwordless sudo. Anything inside the VM, including every token in it,
  should be treated as available to the agents.
- **Tokens** live in `/var/lib/devbox/secrets.env`, mode `0640 root:users`,
  never in git or in a generated config. Give each token the least it needs:
  the `github` MCP server runs `--read-only` and should get a read-only
  token. Use a dedicated Gitea account for the agents rather than your own.
- **The web UI is plain HTTP** with a password and a 30-day session cookie.
  Keep port 4096 on a LAN or a tailnet, or put TLS in front of it, before it
  is reachable from anywhere else.
- **The VM can reach your network.** Nothing here firewalls the VM's outbound
  traffic. If the agents must not reach other machines on your LAN, enforce
  that on the host.
- **Unfree binaries** (Claude Code, the Antigravity CLI) come from nixpkgs and
  are pinned by `flake.lock`. They cannot update themselves.

See [docs/secrets.md](docs/secrets.md) and the "Smaller notes" in
[docs/decisions.md](docs/decisions.md) for the reasoning.

## Reporting a problem

Please use GitHub's **private vulnerability reporting** on this repository
(Security tab → "Report a vulnerability") rather than a public issue. This is
a personal project maintained in spare time: expect a reply within a couple of
weeks.
