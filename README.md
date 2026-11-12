# devbox

A NixOS virtual machine, fully described by this repository, that runs
[opencode](https://opencode.ai) as a headless server with three MCP servers
wired into it.

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
  sshKeys  = [ "ssh-ed25519 AAAA... you@laptop" ];
  secrets  = "none";        # none | file | sops
};
```

Everything else has defaults. `modules/` contains no hostname, disk, port or
user of mine — those are options in `modules/options.nix`. The two things a
fork genuinely has to touch are your SSH key and your disk device
(`hosts/devbox/disko.nix`, `/dev/vda` for a KVM guest).

Nothing here is secret. There is no required `secrets.yaml`, no key to
generate, no re-encryption step: with `secrets = "none"` the machine boots,
opencode serves its web UI, and you log in to a model provider in the browser.

## Secrets: three modes, pick one

| mode | where the credentials live | in git? | setup |
| --- | --- | --- | --- |
| `none` | nowhere — opencode asks you to log in to a provider in the UI | — | none |
| `file` | one env file on the box (`/var/lib/devbox/secrets.env`, root-only) | no | `scripts/secrets-file-init.sh` |
| `sops` | encrypted in this repo, decrypted at boot by the host's age key | ciphertext | `scripts/secrets-sops-init.sh` |

The shipped `hosts/devbox/default.nix` uses `none`. To use sops, set
`secrets = "sops"` there and run `scripts/secrets-sops-init.sh` **before**
installing — the script finishes by evaluating the flake, so a wrong mode or an
uncommitted `secrets.yaml` is reported instead of silently ignored.

**Why `sops` is opt-in and not the default.** sops-nix and agenix both encrypt
*to specific recipients* — that is the whole point, and it is also why they
bind a repo to one deployment: a fork must rekey and re-encrypt, which is
exactly the "changes" a reusable repo should not demand. So the generic path is
`none` or `file`, and `sops` is a deliberate upgrade once a box is yours.

Use `sops` when you want the box rebuildable from the repo alone (no
out-of-band file to lose track of), and you are willing to keep one age
identity backed up. Use `file` when you would rather have no encryption
machinery at all — the VM is the boundary, and the file is root-only and handed
to the service as a systemd credential.

In `sops` mode the secrets are committed **encrypted** (`secrets/secrets.yaml`),
the login password hash included, and the age identity lives only at
`/var/lib/sops-nix/key.txt`. Never commit that file.

## Layout

```
flake.nix                  nixosConfigurations.devbox
hosts/devbox/default.nix   ← the only file you edit
hosts/devbox/disko.nix     disk layout (virtio /dev/vda, GPT + ESP + ext4)
hosts/devbox/hardware.nix  KVM guest profile, systemd-boot
modules/options.nix        every deployment value, with defaults
modules/base.nix           nix flakes, weekly GC, ssh, firewall
modules/users.nix          operator account, sudo policy, authorized keys
modules/secrets.nix        none / file / sops wiring
modules/dev.nix            git, gh, rg, fd, jq, node, python3, uv, bwrap, sops, age
modules/operator.nix       personal extras: vim, nnn, lazygit, shell aliases (delete freely)
modules/mcp.nix            packages + overlay
modules/opencode.nix       systemd unit for `opencode serve`
modules/opencode.json      the three MCP servers
packages/                  opencode 2.2.7, gitea-mcp 1.13.0, serena 2.1.0
scripts/                   secrets init (file + sops), secrets edit, doctor
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
# if you chose sops, this must resolve (it errors when the module is off):
nix eval --raw .#nixosConfigurations.devbox.config.sops.secrets.dev_password_hash.path; echo

sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko -- --mode disko ./hosts/devbox/disko.nix

# only for secrets = "sops": lets the installed system decrypt on first boot
sudo install -Dm600 secrets/devbox.agekey /mnt/var/lib/sops-nix/key.txt

sudo nixos-install --flake .#devbox --no-root-password
reboot
```

sops setup, if you chose it, happens in `scripts/secrets-sops-init.sh`
**before** the install (it prompts, encrypts and commits; it never asks you to
paste values anywhere else).

4. After the reboot, clone the repo again — the `/tmp/devbox` clone lived in the
   installer's memory and is gone. This copy is the one you keep:

```sh
git clone <repo-url> ~/devbox
cd ~/devbox && sudo nixos-rebuild switch --flake .#devbox   # also writes flake.lock
```

Commit that generated `flake.lock`: it pins all four inputs to exact revisions.

## Verify

```sh
sudo devbox-doctor
```

It is a system package (`modules/dev.nix`), so it works without a clone; the
repo copy is the same script at `scripts/doctor.sh`. PASS/FAIL for the secrets
layer (whichever mode), the config symlink and the three servers, the binaries,
the unit state, the listener, the API refusing unauthenticated calls, both forge
tokens against their real APIs, and a live `gitea-mcp` stdio handshake. With
`secrets = "none"` the credential checks are reported as information rather
than failures.

## Day 2

```sh
cd ~/devbox && git pull
sudo nixos-rebuild switch --flake ~/devbox#devbox
```

Roll back with `sudo nixos-rebuild switch --rollback`. Change a secret in sops
mode with `scripts/secrets-edit.sh`, then commit and rebuild — the unit restarts
itself because the template declares `restartUnits`.

## Using it from a phone

`opencode serve` binds `[IP_ADDRESS]:4096` and serves the API and web UI on one
port. Only `/` (the static SPA shell) is public: every `/api/*` call needs HTTP
basic auth (user `opencode`, password `OPENCODE_SERVER_PASSWORD`) — verified, an
unauthenticated `POST /api/session` returns 401. Reach it through an umbrelOS
port forward, or over Tailscale. `opencode pair` prints a one-time pairing link.

Plain HTTP + basic auth is fine on a LAN or tailnet; put TLS in front before
exposing it to the internet.

## Design notes and tradeoffs

- **opencode is a pinned release binary (2.2.7), not a nixpkgs attribute.** The
  26.05 channel still ships 1.15.10, master 2.2.6, upstream 2.2.7. Pinning the
  release keeps the CLI independent of the channel; the checksum comes from
  upstream `SHA256SUMS`.
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
- **Passwords are not declared unless you use sops.** With `users.mutableUsers`
  at its default, a password set with `passwd` survives rebuilds; only sops mode
  declares a hash, because there it is available before the account is created
  (`neededForUsers`).
- **`opencode.json` is a symlink into the nix store** — edit `modules/`, then
  rebuild.
- **GitHub wikis are not reachable over MCP** (they are git repos, not API
  objects); wiki research is the Gitea server's job.
- **Not here yet: the sandbox MCP.** `sandbox_prefetch` (online, through the nix
  daemon) then `sandbox_run` (bwrap: repo rw, store ro, empty home, network
  off). It lands as a tested commit, not blind.
