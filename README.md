# devbox

A NixOS virtual machine, fully described by this repository, that runs
[opencode](https://opencode.ai) as a headless server with three MCP servers
wired into it. [Claude Code](https://code.claude.com) (`claude`) and the
[Antigravity CLI](https://antigravity.google/docs/cli/using/) (`agy`) are there
too, for SSH + tmux, with the same servers and instructions.

| MCP server | What it answers | Source |
| --- | --- | --- |
| `gitea` | issues, PRs, projects, wiki, code search on a Gitea instance — read + write | `gitea/gitea-mcp` 1.13.0, pinned binary |
| `github` | public OSS research: issues, PRs, code search on github.com — **read-only** | `github-mcp-server` (nixpkgs) |
| `serena` | symbol-level codebase navigation over LSP, no index to keep fresh | `serena-agent` 2.1.0 via `uv` |

## Use it for your own box

Fork it, edit **one file**, install.

```nix
# hosts/devbox/default.nix
devbox = {
  hostname = "devbox";
  user     = "dev";
  timeZone = "Europe/Paris";
  webPort  = 4096;
  sshKeyFiles = [ /etc/devbox/authorized_keys ];   # or sshKeys = [ "ssh-ed25519 ..." ]
  docker.enable = true;
};
```

Everything else has defaults. `modules/` contains no hostname, disk, port or
user of mine — those are options in `modules/options.nix`. The two things a
fork genuinely has to touch are your SSH key and your disk device
(`hosts/devbox/disko.nix`, `/dev/vda` for a KVM guest).

Nothing here is secret, and nothing secret is required to boot.

## Secrets: one env file on the box, optional

Credentials live in `/var/lib/devbox/secrets.env` (`devbox.secretsFile`),
mode `0640 root:users`, never in git. It is readable by the operator because
the MCP launchers run as that account (see Terminal agents). `sudo scripts/secrets-file-init.sh` prompts for each
value, writes the file and restarts the service:

| variable | used by |
| --- | --- |
| `OPENCODE_SERVER_PASSWORD` | basic auth on the API/web UI — set it, or opencode invents one per start |
| `GITEA_HOST`, `GITEA_TOKEN` | the `gitea` MCP server |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | the `github` MCP server (read-only PAT) |
| `OPENROUTER_API_KEY` | model provider, if you do not log in through the UI |

The unit reads it with `EnvironmentFile=-…`: a missing file is not an error,
the box just has no credentials and opencode asks you to log in to a provider
in the browser. Changing a value needs a `systemctl restart opencode`, not a
rebuild. Why not sops/agenix: see `docs/decisions.md`.

## Layout

```
flake.nix                  nixosConfigurations.devbox, devShells, checks
hosts/devbox/default.nix   ← the only file you edit
hosts/devbox/disko.nix     disk layout (virtio /dev/vda, GPT + ESP + ext4)
hosts/devbox/hardware.nix  KVM guest profile, systemd-boot
modules/options.nix        every deployment value, with defaults
modules/base.nix           nix flakes, weekly GC, ssh, firewall
modules/users.nix          operator account, sudo policy, authorized keys
modules/dev.nix            toolchain, nix-ld, envfs, direnv, the `devbox` flake registry entry
modules/docker.nix         optional Docker daemon for test suites
modules/operator.nix       personal extras: vim, nnn, lazygit, shell aliases (delete freely)
modules/mcp.nix            packages + overlay, the MCP server set shared by every agent
modules/opencode.nix       systemd unit, generated opencode.json
modules/agents.nix         Claude Code and agy: MCP registration, env hook, instructions
modules/agents-md.nix      the agents' global instructions, one variant per tool
shells.nix                 shared project environments: base, node, python, rust, go
packages/                  gitea-mcp, serena, agent-shell, devbox-project, MCP
                           launchers, Claude env hook, agy wrapper
tests/devbox.nix           VM test: boots the host config, runs devbox-doctor
scripts/                   secrets-file-init, doctor
```

## Install

1. Download the NixOS minimal ISO (~1.4 GB) and upload it to umbrelOS **Files**:
   `https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso`
2. **Machines → Add machine → your own operating system → installer ISO**, sized
   **4 cores / 8192 MB / 80 GB** (suggested values are lower; the nix store
   needs the room).
3. In the machine console:

```sh
git clone <repo-url> /tmp/devbox && cd /tmp/devbox
lsblk     # expect vda; if it is sda, edit hosts/devbox/disko.nix first

# evaluate the whole config first: seconds, and catches Nix errors before
# partitioning a disk
nix eval --raw .#nixosConfigurations.devbox.config.system.build.toplevel.drvPath; echo

sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko -- --mode disko ./hosts/devbox/disko.nix

sudo nixos-install --flake .#devbox --no-root-password
reboot
```

   Alternatively, from a machine that already has Nix, with the installer ISO
   booted and reachable over SSH: `nix run github:nix-community/nixos-anywhere --
   --flake .#devbox root@<ip>` does the partitioning and install in one step.

4. After the reboot, clone the repo again — the `/tmp/devbox` clone lived in the
   installer's memory and is gone. This copy is the one you keep:

```sh
git clone <repo-url> ~/devbox
cd ~/devbox && sudo nixos-rebuild switch --flake .#devbox
sudo scripts/secrets-file-init.sh     # optional, see Secrets
```

## Verify

```sh
sudo devbox-doctor
```

It is a system package (`modules/dev.nix`), so it works without a clone; the
repo copy is the same script at `scripts/doctor.sh`. PASS/FAIL for the secrets
file, the config symlink and the three servers, the agent's environment (PATH,
nix-ld, envfs, the `devbox` registry entry), the binaries,
the unit state, the listener, the API refusing unauthenticated calls, both forge
tokens against their real APIs, and a live `gitea-mcp` stdio handshake. Without a
secrets file the credential checks are reported as information rather
than failures. It exits non-zero on any FAIL, which is what the VM test uses.

## Day 2

```sh
cd ~/devbox && git pull
sudo nixos-rebuild switch --flake ~/devbox#devbox
```

Or push from your laptop without a clone on the box:
`nixos-rebuild switch --flake .#devbox --target-host dev@devbox --use-remote-sudo`.
Roll back with `sudo nixos-rebuild switch --rollback`.

Before deploying a change, try it locally:

```sh
nix flake check          # boots the config in a VM and runs devbox-doctor (needs KVM)
nixos-rebuild build-vm --flake .#devbox && ./result/bin/run-devbox-vm
```

## Logging in to the web UI

`opencode serve` binds `0.0.0.0:4096` and serves the API and web UI on one
port. Every `/api/*` call needs either HTTP basic auth (user `opencode`,
password `OPENCODE_SERVER_PASSWORD`) or a session cookie. Unauthenticated
requests get a 401, verified with `POST /api/session`. Reach the port through
an umbrelOS port forward, or over Tailscale.

A browser, phone included, gets its session cookie from a **pairing link**:

```sh
# on the box: ask the running server for a one-time code
sudo bash -c 'set -eo pipefail; . /var/lib/devbox/secrets.env
  code=$(curl -fsS -u "opencode:$OPENCODE_SERVER_PASSWORD" \
    -X POST http://127.0.0.1:4096/api/pair | jq -r .code)
  ip=$(ip -4 -o addr show scope global | awk "{print \$4}" | cut -d/ -f1 | head -1)
  echo "http://$ip:4096/auth/connect/$code"'
```

Open the printed link in the browser you want to log in. Replace the host and
port if you go through a port forward or a tailnet name. The server checks the
code, sets an `opencode_session_<port>` cookie and redirects to the UI.

- **The link works once and expires after 5 minutes.** Generate a new one for
  each browser. If you open it twice, the second visit says "expired or already
  used".
- **The cookie lasts 30 days** and is `HttpOnly` and `SameSite=Lax`. It's tied
  to the host and port in the link, so pair with the address you'll actually
  use.
- **Sessions are signed with `OPENCODE_SERVER_PASSWORD`.** They survive service
  restarts and rebuilds. Changing the password logs every browser out. Without
  a password in the secrets file, opencode makes up a new one at each start,
  which logs everyone out on every restart. Set one.

**Do not use `opencode pair` on this box.** It only talks to opencode's own
background service, which it finds through `~/.local/state/opencode/service.json`.
Our systemd unit runs plain `opencode serve` and never writes that file, so
`opencode pair` would start a *second* server, with a different port and
password, and print links to that one. (Checked in the 2.2.6 source,
`packages/cli/src/commands/handlers/pair.ts` and `server-process.ts`.)

Avoid the `?auth_token=` query parameter too, even though the server accepts it.
It carries the base64-encoded password in the URL, where it ends up in browser
history.

Plain HTTP is fine on a LAN or tailnet. Put TLS in front before exposing the
port to the internet, because the session cookie travels in clear text.

## Terminal agents: Claude Code and agy

Enabled in the host file (`devbox.claudeCode.enable`,
`devbox.antigravity.enable`). Both are unfree; the flake allows exactly these
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

## Project environments

A public repo almost never ships a Nix environment, and its env files must not
end up in a PR. So the environment lives **next to** the clone, not in it:

```
/srv/work/<name>/
  .envrc          use flake devbox#node    ← not in any git repo
  <name>/         the git checkout, untouched
  wt/<branch>/    git worktrees, which inherit the same env
```

```sh
devbox-project init https://github.com/owner/repo node   # clone; shell: base|node|python|rust|go|upstream|none
devbox-project new foo python                            # empty repo
devbox-project migrate foo                               # old foo/src layout -> foo/foo
```

The checkout is named after the project because opencode names a project after
its folder: with the older `src/` layout every project showed as "src".
`migrate` moves an existing `src/`, repairs its worktrees (wherever they are)
and updates a `use flake ./src` in the `.envrc`. Sessions opened in the old
`src/` path keep their history but point to a folder that no longer exists.

**Creating projects from the web UI.** The web UI can open folders but not
create them, so create projects from a session opened at `/srv/work`: ask
"clone owner/repo" or "start a new project foo", or type
`/new-project <git-url-or-name> [shell]`. Both use the `devbox-project` skill
(`~/.claude/skills/devbox-project/`, read by opencode and Claude Code, where
it is also `/devbox-project`). It runs `devbox-project`, picks the environment
from the repo's files when you don't name one, checks that it builds, and
tells you which folder to open.

**In the web UI, open `/srv/work/<name>/<name>` as the project**, not
`/srv/work/<name>`. opencode recognises a project by its git checkout (keyed by
the remote), and the parent folder is not one: opened there, it lands in
opencode's catch-all "global" project, with no git view, no workspaces, and the
repo's own `AGENTS.md` unread. The environment is unaffected either way, since
the parent `.envrc` is found from the checkout. Sessions started at `/srv/work` are
still the place to create or clone projects.

**Worktrees** are extra checkouts of the same repo on other branches: one per
issue, so parallel sessions don't switch branches under each other. "New
workspace" in the web UI creates one, and the generated `opencode.json` sets
`worktree.directory = "../wt"`, resolved from the main checkout, so it lands
in `/srv/work/<name>/wt/<name>` and shares the project's environment. opencode
shows it under the same project. From a shell or an agent,
`git -C <name> worktree add ../wt/<branch>` does the same. A repo cloned straight
to `/srv/work/<repo>` without `devbox-project init` would put its worktrees in
a shared `/srv/work/wt/`; use the layout.

`shell` is set once, globally, to `agent-shell`. opencode runs every command as
`<shell> -c "<command>"` with cwd set to the project
(`packages/core/src/shell/select.ts` at v2.2.6), and the wrapper picks the
environment:

| found | dispatch |
| --- | --- |
| a `.envrc` **above** the git checkout | `direnv exec <that dir>` — the devbox layout above |
| otherwise the nearest `.envrc` / `flake.nix` from cwd up | `direnv exec` / `nix develop` — what the repo ships itself |
| neither | plain `bash -c` |

The parent `.envrc` wins, so the box stays in control of what runs, and it can
still use an upstream flake with `use flake ./<name>` (`devbox-project init … upstream`).
`direnv allow` happens once per project, not per worktree.

"cwd" is the shell tool's working directory, or the target of a leading
`cd <dir> &&` in the command. That second case covers sessions opened at
`/srv/work` to create or clone a project: there the tool starts in the
workspace root, and agents write `cd /srv/work/foo/foo && make test` rather
than setting the tool's `workdir`. Without that rule the command would run with
no project environment. A `cd` later in the command is not recognised, so
`AGENTS.md` tells the agent to use `workdir`.

Serena picks its project the same way, from the session's directory. In a
`/srv/work` session it has none until the agent calls `activate_project`.
It keeps per-project data in `<project>/.serena/`, which the global git
excludes file keeps out of commits.

`devbox#<name>` is this repo's `devShells` (`shells.nix`), resolved through the
system flake registry, so it is pinned to the deployed revision and needs no
clone. The shells carry system libraries (pkg-config, openssl, zlib, libffi,
sqlite, gcc, make); the version comes from the project's own `.nvmrc`,
`.python-version`, `rust-toolchain.toml` through corepack, uv, mise and rustup.
A project that needs more gets a `flake.nix` next to its `.envrc`.

Beyond Nix environments, the box accepts generic Linux habits: `nix-ld` runs
prebuilt binaries (npm native modules, wheels, rustup/mise toolchains, release
tarballs), `envfs` resolves `#!/bin/bash` and `/usr/bin/python3`, Docker runs
test services, and `devcontainer` covers projects built around `.devcontainer/`.

The agent is told all of this in `~/.config/opencode/AGENTS.md`
(`modules/agents-md.nix`). A project's own `AGENTS.md` adds to it, and a
project-level `opencode.json` / `.opencode/` can still override `shell`, add MCP
servers or set permissions.

## Design notes and tradeoffs

- **opencode comes from `nixpkgs-unstable`, not the 26.05 channel.** The channel
  still ships 1.x. Upstream's release tarball is tempting to pin, but it is
  linked against `/lib64/ld-linux-x86-64.so.2` and **cannot start on NixOS**
  (`stub-ld`); the channel builds it from source with bun instead. The
  `nixpkgs-unstable` input is locked in `flake.lock`, so the version is still
  pinned — just to a build that runs.
- **`gitea-mcp` is still a pinned upstream binary**, and that is safe because it
  is a static Go build with no ELF interpreter (`readelf -l` shows no
  `PT_INTERP`). Anything dynamically linked must not be shipped this way.
- **`devbox-doctor` executes each binary**, not just `command -v`: a prebuilt
  binary can be present and still refuse to start.
- **The documented MCP config shape is wrong for the shipped binary.** The docs
  and the published `opencode.ai/config.json` show `mcp.servers.<name>`; on
  2.2.7 that yields *No MCP servers configured*. The flat `mcp.<name>` record is
  what parses (tested both ways against the real binary).
- **`{env:VAR}` with a missing variable expands to an empty string**, not an
  error, so a forgotten secret looks like an MCP auth failure. `doctor.sh`
  checks each one.
- **The agent has root.** `wheelNeedsPassword = false`, because opencode's shell
  tool is expected to install tooling and rebuild. The containment boundary is
  the VM, not the Unix account.
- **No password is declared.** With `users.mutableUsers` at its default, a
  password set with `passwd` survives rebuilds.
- **`opencode.json` is generated** (`modules/opencode.nix`) with store paths for
  every command, and symlinked into `~/.config/opencode` — edit the module, then
  rebuild.
- **The agent's PATH is the system profile.** The service's `path` is
  `/run/wrappers` + `/run/current-system/sw`, so whatever `modules/` installs is
  what the agent sees. It also sets `DIRENV_CONFIG`, which login shells get from
  `environment.variables` but services do not; without it nix-direnv is never
  loaded and every command re-evaluates the project flake.
- **GitHub wikis are not reachable over MCP** (they are git repos, not API
  objects); wiki research is the Gitea server's job.
- **Not here yet: the sandbox MCP.** `sandbox_prefetch` (online, through the nix
  daemon) then `sandbox_run` (bwrap: repo rw, store ro, empty home, network
  off). It lands as a tested commit, not blind.
