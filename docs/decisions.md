# Decisions

## Why NixOS on a VM

The dev environment needs a real init system, a writable `/nix`, and freedom to
install toolchains without touching the host (umbrelOS here, any KVM host
in general). The VM is also the containment boundary: an agent with root here
cannot reach the host's other services or their data. NixOS makes "what is
installed" a single evaluation, so the running machine and this repo cannot
drift.

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
`programs.nix-ld` (now enabled for what the agent downloads, see below; still
not a reason to ship the system's own services as generic binaries).

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

## Secrets: one optional env file

Credentials are an env file on the box (`devbox.secretsFile`), read by the unit
with `EnvironmentFile=-…`. Missing file, no credentials, the box still boots.

This replaced three modes (`none` / `file` / `sops`). The sops mode was the only
way to rebuild the box from the repo alone, but it cost more than it bought:

- it bound a public repo to one age recipient, so a fork had to rekey;
- `builtins.pathExists secrets/secrets.yaml` made an *untracked* file silently
  behave like no secrets at all (flakes only see tracked files);
- it was the only reason for `LoadCredential`, which hid the file from the
  operator account — an account with passwordless sudo, so it hid nothing.

The VM is the boundary. A file inside it, readable by root and the `users`
group (the MCP launchers run as the operator), backed up with the VM, is the
honest amount of machinery. If rebuilding from git alone becomes a need,
sops-nix can come back as a single path, without the fallbacks.

## The agent's shell is a wrapper, not a setting

A per-project environment could be a per-project `"shell"` value in
`.opencode/opencode.json`. That works, but it makes the environment a thing every
project must remember to declare, and it does nothing for worktrees until each
one is edited.

Instead `shell` is set once, globally, to `agent-shell`, which resolves the
environment from the working directory. The cost is one process hop per
command; the gain is that a project's toolchain is a property of its directory,
so the agent cannot run tests against the wrong interpreter and new worktrees
inherit the behaviour with no configuration.

direnv is preferred over `nix develop` because nix-direnv caches the built
profile: milliseconds against a full flake re-evaluation on every command. That
only holds if the *service* loads nix-direnv: `DIRENV_CONFIG` comes from
`environment.variables`, which systemd units do not get, so the opencode unit
sets it explicitly.

## Project environments live outside the clone

The common task is "fix issue N on a public repository". Such a repository has
no `flake.nix`, and whatever environment the agent adds must never reach the
upstream PR. Putting `.envrc`/`flake.nix` inside the clone means relying on the
agent to never `git add` them, and it collides the day upstream adds its own.

So the layout is `<workspace>/<name>/{.envrc, <name>/, wt/}`, and `agent-shell`
prefers a `.envrc` found **above the git toplevel** over anything inside the
checkout:

- nothing to commit by accident; a global `core.excludesFile` (`.envrc`,
  `.direnv/`, and serena's `.serena/`, whose own `.gitignore` only covers its
  cache) covers the case where the agent creates one inside anyway — it
  only applies to untracked files, so repos that track their own are unaffected;
- every worktree shares one environment and one `direnv allow`;
- the box decides what runs. An upstream `.envrc` is arbitrary shell from the
  internet; it is used only when there is no devbox one, and still needs
  `direnv allow`. An upstream `flake.nix` is opted into with `use flake ./<name>`.

The checkout is `<name>/<name>/`, not `<name>/src/`: opencode names a
project after its checkout's folder, so `src/` made every project "src".

opencode's web UI opens folders but cannot create them. Projects are created
from a session at the workspace root, by the agent, through `devbox-project`
and a `devbox-project` skill in `~/.claude/skills/` (read by both Claude Code
and opencode) plus an opencode `/new-project` command that points to it.

Rejected: nearest-marker-wins (the previous behaviour) — an upstream `.envrc`
or `flake.nix` would shadow the devbox one.

The shared environments (`shells.nix`) are reached as `devbox#<name>` through
`nix.registry.devbox.flake = self`: pinned to the deployed revision, no clone or
network needed. They carry system libraries only. Toolchain *versions* come from
the project's own files (`.nvmrc`, `.python-version`, `rust-toolchain.toml`)
through corepack, uv, mise and rustup, because that is what upstream CI uses and
what the agent will read first.

## Generic Linux affordances: nix-ld and envfs

Agents are trained on Debian-family machines. The failures that matter are not
`apt` itself (the agent can be told) but everything that silently assumes FHS:

| assumption | without help | with |
| --- | --- | --- |
| `/lib64/ld-linux-x86-64.so.2` (npm native modules, uv pythons, rustup/mise toolchains, release tarballs, pre-commit hooks) | `stub-ld`, exit 127 | `programs.nix-ld` + a library set |
| `#!/bin/bash`, `/usr/bin/python3` | not found | `services.envfs` |
| `libstdc++.so.6` for wheels loaded into Nix's own python | ImportError | `LD_LIBRARY_PATH` in `devbox#python` |

This deliberately makes the system tolerant of unpackaged ELF executables, which
the opencode section above avoided for the *system's* own services. The two do
not conflict: the services stay built from source and pinned; nix-ld is for what
the agent downloads into a project, which is disposable by nature.

Escape hatch when a project is built around a container: Docker and the
`devcontainer` CLI are installed, and AGENTS.md tells the agent to prefer them
when a repository ships `.devcontainer/`.

## The agent is told, not left to discover

`~/.config/opencode/AGENTS.md` is generated from `modules/agents-md.nix`: no
apt, where environments live, how to add a library, use Docker for services,
never commit env files, the run ends with a local branch (the GitHub token is
read-only). Everything in it is something an agent would otherwise get wrong at
the start of every task.

## Terminal agents: one server set, each tool's own mechanisms

Claude Code and the Antigravity CLI (`agy`) are used over SSH in tmux, next to opencode. The rule is
that the repo defines *what* they get (three MCP servers, instructions, the
project environment) once, and plugs it in through whatever each tool
officially supports, never by owning a file the tool also writes:

- **MCP servers:** `devbox.mcpServers` (modules/mcp.nix) is the single list.
  opencode's config is generated from it. Claude Code keeps servers in
  `~/.claude.json`, which also holds account state and is rewritten by the
  tool, and agy edits its own `mcp_config.json`, so both are fed through their
  CLIs (`claude mcp add-json --scope user`, `agy mcp add`) by a oneshot unit.
  Rejected: Claude Code's `managed-mcp.json`, which takes *exclusive* control
  (no server of your own, not even with `--mcp-config`), and the
  `managedMcpServers` setting, which only takes remote servers.
- **Tokens:** launchers read the secrets file at start-up, so no agent config
  contains `{env:…}`/`${…}` placeholders that depend on how it was launched
  (systemd unit vs SSH shell). This is why the file became readable by the
  operator group.
- **Environment, Claude Code:** `CLAUDE_CODE_SHELL_PREFIX` would wrap every
  command in `agent-shell`, but Claude Code passes the prefix its whole
  invocation, including its own environment setup, which runs *after* the
  wrapper and could override the project's `PATH`. The documented route for
  direnv-style tools is a `CwdChanged` hook writing to `CLAUDE_ENV_FILE`; it
  lives in `/etc/claude-code/managed-settings.json` (repo-owned, merged with
  the user's own hooks rather than replacing them).
- **Environment, agy:** no hook, prefix or shell setting is documented, so the
  only lever is the process environment: a wrapper resolves the launch
  directory with `agent-shell --resolve` and starts the real binary in it.
- **Instructions:** one generator (`modules/agents-md.nix`) with a per-tool
  "Where commands run" section, because the three tools differ exactly there:
  fresh process per command (opencode), persistent cwd plus hook (Claude Code),
  environment fixed at launch (agy).

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

## Not built yet: a per-command sandbox

The VM already isolates the agent from the host, so per-command jails buy little
*sandboxing* value. What they would buy:

1. hermetic, offline test runs,
2. a command the agent was told to run cannot read `~/.ssh` or the tokens.

Per-project toolchains are already covered by the project environments above.
The planned shape: `sandbox_prefetch` resolves packages online through the nix daemon;
`sandbox_run` executes with bwrap — project bound read-write, `/nix/store`
read-only, empty home, no network unless asked. It would land as a tested
commit, not blind.

## Smaller notes

- **The agent has root.** `wheelNeedsPassword = false`, because the agents are
  expected to install tooling and rebuild. The boundary is the VM, not the
  Unix account.
- **No password is declared.** With `users.mutableUsers` at its default, a
  password set with `passwd` survives rebuilds.
- **`opencode.json` is generated** (`modules/opencode.nix`) with store paths
  for every command and symlinked into `~/.config/opencode`: edit the module,
  then rebuild.
- **The documented MCP config shape is wrong for the shipped binary.** The
  docs and the published `opencode.ai/config.json` show `mcp.servers.<name>`;
  on 2.2.x that yields *No MCP servers configured*. The flat `mcp.<name>`
  record is what parses (tested both ways against the real binary).
- **The agent's PATH is the system profile.** The service's `path` is
  `/run/wrappers` + `/run/current-system/sw`, so whatever `modules/` installs
  is what the agent sees. A hand-picked list once hid gcc, make and docker. The
  unit also sets `DIRENV_CONFIG`, which login shells get from
  `environment.variables` but services do not; without it nix-direnv is never
  loaded and every command re-evaluates the project flake.
- **`devbox-doctor` executes each binary**, not just `command -v`: a prebuilt
  binary can be present and still refuse to start.
- **GitHub wikis are not reachable over MCP** (they are git repos, not API
  objects); wiki research is the Gitea server's job.

## Rejected

- **Docker-in-VM for the agent toolchain**: a second daemon and image layer
  where nix derivations are enough.
- **`nix-sandbox-mcp` / `mcp-nix` / `nix-exec`**: 0–16 stars, and the first
  mounts the project read-only, which breaks test artifacts.
- **Running Antigravity's IDE or Agent Manager against the VM**: the Agent
  Manager works on local folders only, and the IDE would need remote-SSH. The
  CLI (`agy`) covers the SSH + tmux workflow instead; see below.
