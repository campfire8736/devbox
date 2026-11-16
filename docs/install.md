# Install and operate

## Before you start

- **A KVM host** that can boot an ISO: umbrelOS (the worked example below),
  libvirt/virt-manager, Proxmox, plain QEMU. x86_64 only.
- **A VM of 4 cores, 8 GB RAM, 80 GB disk.** Hosts often suggest less; the
  nix store needs the room.
- **Your edits to `hosts/devbox/default.nix`**: at least the SSH key and, if
  your VM's disk is not `/dev/vda`, the device in `hosts/devbox/disko.nix`.

## Option A: from the installer console

Example on umbrelOS. Other hosts differ only in steps 1 and 2.

1. Download the NixOS minimal ISO (~1.4 GB) and upload it to umbrelOS
   **Files**:
   `https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso`
2. **Machines → Add machine → your own operating system → installer ISO**,
   sized as above.
3. In the machine console:

   ```sh
   git clone https://github.com/campfire8736/devbox /tmp/devbox && cd /tmp/devbox
   lsblk     # expect vda; if it is sda, edit hosts/devbox/disko.nix first

   # evaluate the whole config first: seconds, and catches Nix errors before
   # partitioning a disk
   nix --extra-experimental-features 'nix-command flakes' \
     eval --raw .#nixosConfigurations.devbox.config.system.build.toplevel.drvPath; echo

   sudo nix --extra-experimental-features 'nix-command flakes' \
     run github:nix-community/disko -- --mode disko ./hosts/devbox/disko.nix

   sudo nixos-install --flake .#devbox --no-root-password
   reboot
   ```

4. After the reboot, clone the repo again (use your fork if you have one).
   The `/tmp/devbox` clone lived in the installer's memory and is gone. This
   copy is the one you keep:

   ```sh
   git clone https://github.com/campfire8736/devbox ~/devbox
   cd ~/devbox && sudo nixos-rebuild switch --flake .#devbox
   sudo scripts/secrets-file-init.sh     # optional, see secrets.md
   ```

## Option B: from another machine with Nix

Boot the installer ISO, give it a root password or key so it is reachable over
SSH, then from your machine:

```sh
nix run github:nix-community/nixos-anywhere -- --flake .#devbox root@<vm-ip>
```

It partitions, installs and reboots in one step. Then do step 4 above on the
box, or deploy from your machine (see Day 2).

## Verify

```sh
sudo devbox-doctor
```

It is a system package (`modules/dev.nix`), so it works without a clone; the
repo copy is the same script at `scripts/doctor.sh`. It prints PASS or FAIL
for:

- the secrets file, the generated config and the three MCP servers;
- the agent's environment: PATH, nix-ld, envfs, the `devbox` registry entry;
- every binary, executed rather than just found: a prebuilt binary can be
  present and still refuse to start;
- the opencode unit, its listener, and the API refusing unauthenticated calls;
- both forge tokens against their real APIs, and a live `gitea-mcp` handshake;
- Claude Code and the Antigravity CLI (`agy`), when enabled: MCP registration, instructions, the
  environment hook.

Without a secrets file the credential checks are reported as information,
not failures. It exits non-zero on any FAIL, which is what the VM test uses.

## Day 2

```sh
cd ~/devbox && git pull
sudo nixos-rebuild switch --flake ~/devbox#devbox
```

Or deploy from your machine, without a clone on the box:

```sh
nixos-rebuild switch --flake .#devbox --target-host dev@devbox --use-remote-sudo
```

Roll back with `sudo nixos-rebuild switch --rollback`.

Try a change locally before deploying it:

```sh
nix flake check          # boots the config in a VM and runs devbox-doctor (needs KVM)
nixos-rebuild build-vm --flake .#devbox && ./result/bin/run-devbox-vm
```
