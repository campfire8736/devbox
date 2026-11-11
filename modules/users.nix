{ ... }:
{
  users.users.dev = {
    isNormalUser = true;
    description = "devbox operator + opencode service account";
    extraGroups = [ "wheel" ];
    # The login password hash lives in secrets/secrets.yaml (sops-nix), so it is
    # never in this repo. Until the secrets file exists the account is key-only.
    openssh.authorizedKeys.keys = [
      # PUBLIC keys only — replace with yours and commit.
      # "ssh-ed25519 AAAA... you@laptop"
    ];
  };

  # Passwordless sudo is deliberate: opencode's shell tool runs as `dev` and is
  # expected to install tooling and rebuild the system. The containment boundary
  # is the VM, not the Unix account. Set to true to gate sudo behind a password.
  security.sudo.wheelNeedsPassword = false;
}
