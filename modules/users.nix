{ config, lib, ... }:
let
  cfg = config.devbox;
  haveSopsPassword = cfg.secrets == "sops" && builtins.pathExists ../secrets/secrets.yaml;
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
      assertion = haveSopsPassword || cfg.sshKeys != [ ];
      message = ''
        devbox: no way to log in. With devbox.secrets != "sops" (or sops selected
        but secrets/secrets.yaml missing) there is no login password, so
        devbox.sshKeys must contain at least one PUBLIC key.
      '';
    }
  ];

  # Passwordless sudo is deliberate: opencode's shell tool runs as the operator
  # and is expected to install tooling and rebuild. The containment boundary is
  # the VM, not the Unix account.
  security.sudo.wheelNeedsPassword = false;
}
