# devbox

A NixOS virtual machine, fully described by this repository, that runs
[opencode](https://opencode.ai) as a headless server with three MCP servers
wired into it.

| MCP server | What it answers | Source |
| --- | --- | --- |
| `gitea` | issues, PRs, projects, wiki, code search on a Gitea instance — read + write | `gitea/gitea-mcp` 1.13.0, pinned binary |
| `github` | public OSS research: issues, PRs, code search on github.com — **read-only**, toolsets `repos,issues,pull_requests` | `github-mcp-server` (nixpkgs) |
| `serena` | symbol-level codebase navigation (find symbol, references, callers) over LSP, no index to keep fresh | `serena-agent` 2.1.0 via `uv` |

Nothing is installed by hand: the VM is rebuilt from this repo and every change
is a commit.

**This repository is public and contains no secrets.** Login hash, tokens and
the API key are committed **encrypted** with sops + age (`secrets/secrets.yaml`).
The age identity lives only on the machine, at `/var/lib/sops-nix/key.txt`.

## Layout

```
flake.nix                  entry point: nixosConfigurations.devbox
hosts/devbox/              disk layout (disko), KVM hardware, imports
modules/base.nix           nix flakes, weekly GC, ssh, firewall 22 + 4096
modules/users.nix          user `dev`, wheel, passwordless sudo, authorized keys
modules/secrets.nix        sops-nix wiring: secrets -> env template + login hash
modules/dev.nix            git, gh, rg, fd, jq, node 22, python3, uv, bwrap, sops, age
modules/mcp.nix            packages + overlay
modules/opencode.nix       systemd unit for `opencode serve` on :4096
modules/opencode.json      the three MCP servers
packages/                  opencode 2.2.7, gitea-mcp 1.13.0, serena 2.1.0
scripts/bootstrap-secrets.sh  creates the age identity + encrypted secrets
scripts/doctor.sh             PASS/FAIL health check
scripts/secrets-edit.sh       edit secrets with the host key
secrets.example.yaml          shape of the encrypted file, no values
```

## Install

### 1. Add your SSH key

`modules/users.nix` ships an empty `authorizedKeys` list on purpose. Add your
**public** key there and commit — before installing, because the account is
key-only until the encrypted login hash is active.

```nix
openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... you@laptop" ];
```

### 2. Create the machine

Download the NixOS minimal ISO (~1.4 GB) and upload it to umbrelOS **Files**:

```
https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso
```

Then **Machines → Add machine → your own operating system → installer ISO**,
and size it **4 cores / 8192 MB / 80 GB**. The suggested values are lower; the
nix store needs the room.

### 3. Create the secrets (in the installer, before installing)

`<your-gitea-host>` below is whatever your Gitea is reachable at *from inside
the VM* — for a NAS-local install that is its LAN address and port.

```sh
export NIX_CONFIG="experimental-features = nix-command flakes"
git clone http://<your-gitea-host>/<owner>/devbox /tmp/devbox
cd /tmp/devbox
bash scripts/bootstrap-secrets.sh     # prompts for each value, encrypts, commits
```

It generates an age identity at `secrets/devbox.agekey`, writes `.sops.yaml`
with the matching public key, and leaves you an encrypted
`secrets/secrets.yaml`. **Back up the identity file now** — it is gitignored and
without it the secrets cannot be recovered. Push the commit when you can.

### 4. Install

```sh
lsblk     # expect vda; if the disk is sda, edit hosts/devbox/disko.nix first

sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko -- --mode disko ./hosts/devbox/disko.nix

# lets the installed system decrypt its own secrets on first boot
sudo install -Dm600 secrets/devbox.agekey /mnt/var/lib/sops-nix/key.txt

sudo nixos-install --flake .#devbox --no-root-password
reboot
```

## Verify

```sh
sudo bash ~/devbox/scripts/doctor.sh
```

PASS/FAIL for: age identity, rendered env file, every secret present (length
only, never values), config symlink and the three servers, binaries, unit
state, listener on 4096, the API refusing unauthenticated calls, both forge
tokens against their real APIs, and a live `gitea-mcp` stdio handshake.

## Day 2

```sh
git clone http://<your-gitea-host>/<owner>/devbox ~/devbox   # once
cd ~/devbox && git pull
sudo nixos-rebuild switch --flake ~/devbox#devbox
```

Roll back with `sudo nixos-rebuild switch --rollback`. Change a secret with
`scripts/secrets-edit.sh`, then commit and rebuild.

## Using it from a phone

The server binds `0.0.0.0:4096` and serves both the API and the web UI. Only
`/` (the static SPA shell) is public; every `/api/*` call needs HTTP basic auth
(user `opencode`, password `OPENCODE_SERVER_PASSWORD`) — verified: an
unauthenticated `POST /api/session` returns 401.

Reach it through an umbrelOS port forward (`40023 → 4096` web, `40024 → 22`
ssh), or over Tailscale using the NAS tailnet address and the same port.
`opencode pair` prints a one-time pairing link for the browser or the app.

Plain HTTP + basic auth is fine on a LAN or tailnet; do not expose 4096 to the
internet without TLS in front of it.

## Design notes and tradeoffs

- **opencode is a pinned release binary (2.2.7), not nixpkgs.** The 26.05
  channel still ships 1.15.10; the binary keeps the CLI version independent of
  the channel. Checksum is from upstream `SHA256SUMS`.
- **The documented MCP config shape is wrong for the shipped binary.** The docs
  and the published `opencode.ai/config.json` show `mcp.servers.<name>`; on
  2.2.7 that produces *No MCP servers configured*. The flat `mcp.<name>` record
  is what actually parses (tested both ways against the real binary).
- **`{env:VAR}` with a missing variable expands to an empty string**, not an
  error, so a forgotten secret looks like an auth failure rather than a config
  error. `doctor.sh` checks each one separately.
- **The agent has root.** `wheelNeedsPassword = false`, because opencode's shell
  tool is expected to install tooling and rebuild. The containment boundary is
  the VM, not the Unix account.
- **Secrets are ciphertext in git.** sops-nix decrypts at activation into
  `/run/secrets-rendered/`, and the unit receives it through systemd
  `LoadCredential`, so `dev` cannot read the file. The login hash is marked
  `neededForUsers` so it exists before the user account is created.
- **`opencode.json` is a symlink into the nix store** — edit `modules/`, not the
  file, then rebuild.
- **GitHub wikis are not reachable over MCP** (they are git repos, not API
  objects). Wiki research is the Gitea server's job.
- **Not here yet: the sandbox MCP.** `sandbox_prefetch` (online, through the nix
  daemon) then `sandbox_run` (bwrap: repo rw, store ro, empty home, network
  off). It lands as a tested commit, not blind.
