# Decisions

## Why NixOS on a VM

The dev environment needs a real init system, a writable `/nix`, and freedom to
install toolchains without touching umbrelOS. The VM is also the containment
boundary: an agent with root here cannot reach the NAS apps or the Gitea data
directory. NixOS makes "what is installed" a single
evaluation, so the running machine and this repo cannot drift.

## Why opencode comes from nixpkgs-unstable

`nixos-26.05` carries 1.15.10; `master` carries 2.x and builds it from source
with bun. Upstream also publishes `opencode-linux-x64.tar.gz`, and pinning that
looked like the tidy answer — exact version, checksummed, no channel coupling.

It does not run on NixOS. The release binary carries
`PT_INTERP /lib64/ld-linux-x86-64.so.2`, so the kernel looks for a loader path
that NixOS deliberately does not provide, and the unit dies with status 127:

```
Could not start dynamically linked executable: .../opencode-2.2.7/bin/opencode
NixOS cannot run dynamically linked executables intended for generic linux environments
```

So the package comes from the `nixpkgs-unstable` input instead. Version
independence is preserved by `flake.lock` rather than by a hand-written
`fetchurl` — the pin just points at a build that can start.

`gitea-mcp` remains a pinned release binary because it is a static Go build with
no interpreter at all; that is the distinction that matters, not "prebuilt or
not". If a future tool only ships a dynamic binary, the options are, in order:
package it with `autoPatchelfHook`, build from source in the flake, or enable
`programs.nix-ld` (the documented escape hatch for generic Linux binaries, at
the cost of making the system tolerant of unpackaged ELF executables).

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

## Secrets: three modes, and why the repo does not depend on one

The repo is public and meant to be forked. Those two facts rule out baking any
particular secret store into the flake, because every nix-native option has the
same property: encryption is bound to specific recipients.

| approach | keeps secrets in git | cost to a fork |
| --- | --- | --- |
| sops-nix (age/GPG) | yes, ciphertext | new age identity + re-encrypt |
| agenix | yes, ciphertext | new SSH host key + `agenix -r` rekey |
| plain env file on the box | no | nothing |
| credential store at runtime (Vault, 1Password, Bitwarden CLI) | no | a dependency and a bootstrap token |

So the flake exposes `devbox.secrets = "none" | "file" | "sops"` with `none` as
the default. A fork boots and works with no secret setup at all; opencode asks
you to log in to a provider in the UI. `file` is the boring middle ground: one
root-only env file, handed to the service as a systemd credential, never in git.
`sops` is the opt-in used here, because it is the only option that lets the box
be rebuilt from the repo alone.

Two details that make sops mode correct rather than convenient:

- `neededForUsers = true` on the login hash, so it exists before the account is
  created — otherwise the account comes up key-only after boot.
- the rendered env file is passed via `LoadCredential`, so the operator account
  (and any agent running as it) cannot read it.

Rejected: declaring a password hash in the plain flake (a public repo invites
offline cracking of a dev password), and requiring sops for every fork (it is
the single largest source of "works on my machine" in NixOS configs).

## The agent's shell is a wrapper, not a setting

A per-project environment could be a per-project `"shell"` value in
`.opencode/opencode.json`. That works, but it makes the environment a thing every
project must remember to declare, and it does nothing for worktrees until each
one is edited.

Instead `shell` is set once, globally, to `agent-shell`, which resolves the
environment from the working directory (`.envrc` → `direnv exec`, else
`flake.nix` → `nix develop`). The cost is one process hop per command; the gain
is that a project's toolchain is a property of its directory, so the agent cannot
run tests against the wrong interpreter and new worktrees inherit the behaviour
with no configuration.

direnv is preferred over `nix develop` because nix-direnv caches the built
profile: milliseconds against a full flake re-evaluation on every command.

## SSH keys: out of git by default

Public keys are safe to publish, but they are also *yours*: a key in a shared
repo is a change conflict waiting to happen, and a fork that keeps them
elsewhere should not have to edit a tracked file. So the recommended path is
`devbox.sshKeyFiles`, a path on the machine read at evaluation time into
`/etc/ssh/authorized_keys.d/<user>`.

The `types.path` option is deliberate: a missing file fails evaluation, which is
what a typo should do. `lib.readFile` also means a rebuild is required after a
key changes — the trade against keeping keys in git, where a rebuild is required
anyway.

The third route (`manualSshKeys = true`) works because NixOS skips generating
`authorized_keys.d` entirely when the declarative lists are empty, leaving
`~/.ssh/authorized_keys` under your own control.

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
