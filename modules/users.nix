{ config, lib, ... }:
let
  cfg = config.devbox;
  haveSopsPassword = cfg.secrets == "sops" && builtins.pathExists ../secrets/secrets.yaml;
  haveKeys = cfg.sshKeys != [ ] || cfg.sshKeyFiles != [ ];
in
{
  # Exactly one assignment: `users.users.${cfg.user}` is a dynamic attribute, and
  # Nix rejects the same dynamic key twice in one attrset literal ("dynamic
  # attribute 'dev' already defined"). mkMerge joins the two definitions instead.
  users.users.${cfg.user} = lib.mkMerge [
    {
      isNormalUser = true;
      description = "operator + opencode service account";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.sshKeys;
      openssh.authorizedKeys.keyFiles = cfg.sshKeyFiles;
    }
    # Declaring a login password is a deployment choice, so it is only declared in
    # sops mode. `users.mutableUsers` stays at its default (true), so a password
    # set with `passwd` survives rebuilds in the other modes.
    (lib.mkIf haveSopsPassword {
      hashedPasswordFile = config.sops.secrets.dev_password_hash.path;
    })
  ];

  # Hard guard: with no declared password the account is key-only, so an empty
  # key list would leave a machine nothing can log in to.
  assertions = [
    {
      assertion = haveSopsPassword || haveKeys || cfg.manualSshKeys;
      message = ''
        devbox: no way to log in. There is no login password (secrets != "sops",
        or the encrypted file is missing) and no key declared. Set one of:
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
