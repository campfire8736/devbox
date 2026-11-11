{ config, lib, ... }:
let
  cfg = config.devbox;
  haveSopsPassword = cfg.secrets == "sops" && builtins.pathExists ../secrets/secrets.yaml;
in
{
  users.users.${cfg.user} = {
    isNormalUser = true;
    description = "operator + opencode service account";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = cfg.sshKeys;
  };

  # Declaring a login password is a deployment choice, so it is only declared in
  # sops mode. `users.mutableUsers` stays at its default (true), which means a
  # password set with `passwd` survives rebuilds in the other modes.
  users.users.${cfg.user} = lib.mkIf haveSopsPassword {
    hashedPasswordFile = config.sops.secrets.dev_password_hash.path;
  };

  # Passwordless sudo is deliberate: opencode's shell tool runs as the operator
  # and is expected to install tooling and rebuild. The containment boundary is
  # the VM, not the Unix account.
  security.sudo.wheelNeedsPassword = false;
}
