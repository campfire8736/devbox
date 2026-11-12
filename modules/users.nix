{ config, ... }:
let
  cfg = config.devbox;
  haveKeys = cfg.sshKeys != [ ] || cfg.sshKeyFiles != [ ];
in
{
  # No password is declared: `users.mutableUsers` stays at its default (true), so
  # a password set with `passwd` survives rebuilds.
  users.users.${cfg.user} = {
    isNormalUser = true;
    description = "operator + opencode service account";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = cfg.sshKeys;
    openssh.authorizedKeys.keyFiles = cfg.sshKeyFiles;
  };

  # Hard guard: password SSH login is off, so an empty key list would leave a
  # machine nothing can log in to.
  assertions = [
    {
      assertion = haveKeys || cfg.manualSshKeys;
      message = ''
        devbox: no way to log in. Password SSH login is disabled and no key is
        declared. Set one of:
          devbox.sshKeys      - inline public keys (these go into git)
          devbox.sshKeyFiles  - paths to key files, read at build time
          devbox.manualSshKeys = true - if you manage ~/.ssh/authorized_keys yourself
      '';
    }
  ];

  # Passwordless sudo is deliberate: opencode's shell tool runs as the operator
  # and is expected to install tooling and rebuild. The containment boundary is
  # the VM, not the Unix account.
  security.sudo.wheelNeedsPassword = false;
}
