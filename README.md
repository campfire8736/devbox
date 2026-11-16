# devbox

[![check](https://github.com/campfire8736/devbox/actions/workflows/check.yml/badge.svg)](https://github.com/campfire8736/devbox/actions/workflows/check.yml)

A NixOS virtual machine, described entirely by this repository, for AI coding
agents that need a whole machine: install toolchains, run test suites, start
Docker services, rebuild the system. The agents get root inside the VM; the VM
is the security boundary.

It runs [opencode](https://opencode.ai) as a web UI you reach from a browser
or phone. [Claude Code](https://code.claude.com) and the
[Antigravity CLI](https://antigravity.google/docs/cli/using/) are there for
SSH and tmux. All three get the same MCP servers and instructions.

## What you get

- **opencode as a service**, with its web UI on port 4096 behind a password,
  and login by one-time pairing link.
- **Claude Code (`claude`) and agy**, optional, set up the same way.
- **Three MCP servers** for every agent:

  | server | what it answers |
  | --- | --- |
  | `gitea` | issues, PRs, projects, wiki, code search on a Gitea instance, read and write |
  | `github` | public OSS research on github.com: issues, PRs, code search, **read-only** |
  | `serena` | symbol-level code navigation through real language servers |

- **Per-project environments kept out of git.** Each project lives in
  `/srv/work/<name>/`, with the checkout inside it and the Nix environment
  (`.envrc`) next to it, so nothing ends up in an upstream PR. Every agent
  command runs in that environment.
- **A NixOS that tolerates Ubuntu habits.** `nix-ld` runs prebuilt binaries,
  `envfs` resolves `#!/bin/bash`, and the agents are told there is no `apt`
  and what to do instead.
- **`devbox-doctor`**, a health check, and a VM test (`nix flake check`) that
  boots the config and runs it.

## Requirements

- An x86_64 KVM host that can boot an ISO. Tested on umbrelOS; libvirt,
  Proxmox or plain QEMU work the same way.
- A VM of 4 cores, 8 GB RAM and 80 GB of disk.
- An account with a model provider (opencode can log in to one from the web
  UI), plus a Claude account or Google account for `claude` or `agy`.

Claude Code and the Antigravity CLI are unfree software. The flake allows
exactly these two by name; set `claudeCode.enable` and `antigravity.enable` to
`false` to leave them out.

## Quick start

1. **Fork the repo and edit one file**, `hosts/devbox/default.nix`:

   ```nix
   devbox = {
     hostname = "devbox";
     user     = "dev";
     timeZone = "Europe/Paris";
     webPort  = 4096;
     sshKeys  = [ "ssh-ed25519 AAAA... you@laptop" ];   # or sshKeyFiles, or manualSshKeys
     docker.enable      = true;
     claudeCode.enable  = true;
     antigravity.enable = true;
   };
   ```

   If the VM's disk is not `/dev/vda`, change it in `hosts/devbox/disko.nix`.

2. **Install.** Boot the NixOS minimal ISO in the VM, then from a machine with
   Nix:

   ```sh
   nix run github:nix-community/nixos-anywhere -- --flake .#devbox root@<vm-ip>
   ```

   Or install from the VM's own console:
   [docs/install.md](docs/install.md) has both paths step by step.

3. **Add credentials** (all optional) and check the box:

   ```sh
   sudo scripts/secrets-file-init.sh   # web UI password, forge tokens, API key
   sudo devbox-doctor
   ```

4. **Log in to the web UI** with a one-time pairing link:

   ```sh
   sudo bash -c 'set -eo pipefail; . /var/lib/devbox/secrets.env
     code=$(curl -fsS -u "opencode:$OPENCODE_SERVER_PASSWORD" \
       -X POST http://127.0.0.1:4096/api/pair | jq -r .code)
     echo "http://<vm-address>:4096/auth/connect/$code"'
   ```

   Open the link in the browser you want to log in, within 5 minutes. Details
   and pitfalls: [docs/web-ui.md](docs/web-ui.md).

## Working with it

- **Start a project** from a web UI session opened at `/srv/work`: ask
  "clone owner/repo", or type `/new-project <git-url> [shell]`. The agent
  creates the layout and its environment.
- **Work on it** by opening `/srv/work/<name>/<name>` as a project. "New
  workspace" gives each issue its own git worktree, in `<name>/wt/`.
- **From a terminal:** `ssh dev@devbox -t tmux new -A -s main`, then
  `cd /srv/work/<name>/<name>` and run `claude` or `agy`.
- **Change the box** by editing this repo and running
  `sudo nixos-rebuild switch --flake ~/devbox#devbox`. Roll back with
  `--rollback`.

## Documentation

| | |
| --- | --- |
| [docs/install.md](docs/install.md) | install, verify, update, test locally |
| [docs/secrets.md](docs/secrets.md) | the secrets file, and running without a Gitea server |
| [docs/web-ui.md](docs/web-ui.md) | logging in with a pairing link, cookies, what not to use |
| [docs/projects.md](docs/projects.md) | project layout, creation, worktrees, how commands get their environment |
| [docs/terminal-agents.md](docs/terminal-agents.md) | Claude Code and agy over SSH |
| [docs/decisions.md](docs/decisions.md) | why things are the way they are, and what was rejected |

## Repository layout

```
flake.nix                  nixosConfigurations.devbox, devShells, checks
hosts/devbox/              the example host: default.nix is the file you edit
modules/options.nix        every deployment value, with defaults
modules/                   base system, users, toolchain, docker, MCP servers,
                           opencode, terminal agents, agent instructions
modules/operator.nix       personal shell extras (vim, nnn, lazygit); delete freely
shells.nix                 shared project environments: base, node, python, rust, go
packages/                  agent-shell, devbox-project, MCP launchers, serena,
                           gitea-mcp, Claude env hook, agy wrapper
tests/devbox.nix           VM test: boots the host config, runs devbox-doctor
scripts/                   secrets-file-init, doctor
```

## Status

A personal project, used daily on one box. Expect rough edges:

- **The agents have root**, with passwordless sudo, by design. Treat the VM
  as something they control.
- **The web UI is plain HTTP.** Keep it on a LAN or a tailnet, or put TLS in
  front, since the session cookie travels in clear text.
- **x86_64 only**, and the docs assume a KVM guest.

Security notes and how to report a problem: [SECURITY.md](SECURITY.md).

## License

Copyright 2026 campfire8736. Licensed under the
[Apache License 2.0](LICENSE).
