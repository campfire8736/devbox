# Decisions

## Why NixOS on a VM

The dev environment needs a real init system, a writable `/nix`, and freedom to
install toolchains without touching umbrelOS. The VM is also the containment
boundary: an agent with root here cannot reach the NAS apps or the Gitea data
directory. NixOS makes "what is installed" a single
evaluation, so the running machine and this repo cannot drift.

## Why a pinned opencode binary instead of a nixpkgs attribute

`nixos-26.05` carries 1.15.10; `master` carries 2.2.6; upstream is at 2.2.7.
Upstream publishes `opencode-linux-x64.tar.gz` with a `SHA256SUMS` file, so the
binary can be pinned and verified the same way as `gitea-mcp`, and the CLI
version stops tracking the channel. Revisit if nixpkgs catches up and the
channel is bumped.

## Why gitea-mcp rather than the GitHub server for our own code

`gitea-mcp` covers `repository`, `file`, `branch`, `issue`, `pull_request`,
`project`, `wiki` and `search` — including Gitea *Projects* (boards), the
closest thing to GitHub Projects v2. The GitHub server stays read-only and
limited to `repos,issues,pull_requests`, and exists only for public OSS
research.

## Why Serena for codebase search, not Graphify

Graphify's hosted MCP indexes **GitHub** repositories, so it cannot see a
self-hosted Gitea. Its local engine works anywhere but needs a graph build per
repo kept current. Serena drives real language servers: exact about symbols,
never stale. If call-graph or impact queries turn out to be the gap, add local
Graphify as a fourth server rather than replacing Serena.

## Secrets: sops-nix with an age identity, ciphertext in git

The repository is public, so nothing sensitive may be committed in the clear.
sops-nix gives encrypted-at-rest secrets that still live in git, so the box
stays reproducible from the repo alone. The identity file is the one thing
outside version control; losing it means re-encrypting.

`neededForUsers = true` on the login hash is what makes the password exist
before the account is created — otherwise the account is key-only after boot.
The rendered env file is handed to the unit as a systemd credential rather than
being readable by the `dev` user.

Rejected: plaintext `EnvironmentFile` on the box (not reproducible, drifts from
the repo), and committing a password hash unencrypted (a public repo invites
offline cracking of a dev password).

## Sandbox: what it is for

The VM already isolates the agent from the NAS, so per-command jails buy little
*sandboxing* value. What they buy:

1. per-project toolchains that never pollute the system profile (nix flakes),
2. hermetic, offline test runs,
3. a command the agent was told to run cannot read `~/.ssh`, the tokens, or the
   age identity.

Shape: `sandbox_prefetch` resolves packages online through the nix daemon;
`sandbox_run` executes with bwrap — project bound read-write, `/nix/store`
read-only, empty home, no network unless asked.

## Rejected

- **Docker-in-VM for the agent toolchain**: a second daemon and image layer
  where nix derivations are enough.
- **`nix-sandbox-mcp` / `mcp-nix` / `nix-exec`**: 0–16 stars, and the first
  mounts the project read-only, which breaks test artifacts.
- **Running Antigravity's IDE in the VM**: the CLI works headless, but the
  Agent Manager is local-only and the IDE needs remote-SSH. Revisit if that
  becomes the main workflow.
