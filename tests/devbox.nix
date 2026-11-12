# Boots the real host configuration in a VM and checks what the agent depends
# on. Run with `nix flake check` (needs KVM and a few GB for the closure).
{ pkgs, self }:
pkgs.testers.runNixOSTest {
  name = "devbox";

  # the host config adds an overlay, so it needs its own nixpkgs instance
  node.pkgsReadOnly = false;
  node.specialArgs = {
    unstable = self.inputs.nixpkgs-unstable;
    devboxFlake = self;
  };

  nodes.machine = {
    imports = [
      self.inputs.disko.nixosModules.disko
      ../hosts/devbox
    ];
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      diskSize = 8192;
    };
    # a known UI password, so the doctor exercises the authenticated path
    environment.etc."devbox-test.env".text = "OPENCODE_SERVER_PASSWORD=test-password\n";
    devbox.secretsFile = "/etc/devbox-test.env";
  };

  testScript = ''
    machine.wait_for_unit("opencode.service")
    machine.wait_for_open_port(4096)

    # the agent sees the whole system profile, not a hand-picked list
    machine.succeed(
      "tr '\\0' '\\n' < /proc/$(systemctl show -p MainPID --value opencode)/environ"
      " | grep -q '^PATH=.*/run/current-system/sw/bin'"
    )
    machine.succeed(
      "tr '\\0' '\\n' < /proc/$(systemctl show -p MainPID --value opencode)/environ"
      " | grep -q '^DIRENV_CONFIG=/etc/direnv$'"
    )

    # generic-Linux affordances: /bin/bash shebangs and the FHS loader
    machine.succeed("/usr/bin/env bash -c true")
    machine.succeed("test -e /lib64/ld-linux-x86-64.so.2")

    # parent .envrc wins over one inside the clone
    machine.succeed(
      "su - dev -c '"
      "mkdir -p /srv/work/p/src && cd /srv/work/p"
      " && echo export WHO=parent > .envrc && echo export WHO=clone > src/.envrc"
      " && git -C src init -q && direnv allow . && direnv allow src"
      " && cd src && test \"$(agent-shell -c \"echo \\$WHO\")\" = parent'"
    )

    # serena is fetched through uv on first run; the VM has no network
    machine.succeed("DEVBOX_DOCTOR_OFFLINE=1 devbox-doctor >&2")
  '';
}
