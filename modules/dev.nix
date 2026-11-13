{ config, pkgs, devboxFlake, ... }:
let
  cfg = config.devbox;

  # The health check must not depend on a git clone being present: the install
  # runs from the installer's /tmp, which is gone after the first reboot.
  doctor = pkgs.writeShellScriptBin "devbox-doctor" ''
    export DEVBOX_USER=${cfg.user}
    export DEVBOX_PORT=${toString cfg.webPort}
    export DEVBOX_SECRETS_FILE=${cfg.secretsFile}
    export DEVBOX_CLAUDE=${if cfg.claudeCode.enable then "1" else ""}
    export DEVBOX_AGY=${if cfg.antigravity.enable then "1" else ""}
    exec ${pkgs.bash}/bin/bash ${../scripts/doctor.sh} "$@"
  '';

  # Untracked files only: a repo that tracks its own .envrc is unaffected.
  # .serena/ is serena's per-project data (project.yml, memories, caches). Its
  # own .serena/.gitignore only covers the cache, so without this an agent's
  # `git add -A` would put it in an upstream PR.
  gitExcludes = pkgs.writeText "gitignore-global" ''
    .envrc
    .direnv/
    .serena/
  '';
in
{
  environment.systemPackages = with pkgs; [
    git
    gh
    ripgrep
    fd
    jq
    yq-go
    tree
    tmux
    htop
    unzip
    nodejs
    python3
    uv
    bubblewrap
    gnumake
    gcc
    pkg-config
    # version managers: the project's own version files pick the toolchain
    mise
    rustup
    # for projects built around .devcontainer/
    devcontainer
    doctor
  ];

  # Generic Linux binaries (npm native modules, pip wheels in uv-managed
  # pythons, rustup/mise toolchains, release tarballs) expect the FHS loader at
  # /lib64/ld-linux-x86-64.so.2. nix-ld provides it, plus these libraries.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      zstd
      openssl
      curl
      libffi
      libxml2
      libuuid
      ncurses
      sqlite
      expat
      icu
      bzip2
      xz
      glib
      libsecret
      util-linux
    ];
  };

  # `#!/bin/bash`, `/usr/bin/python3` and friends resolve through the caller's
  # PATH instead of failing: NixOS itself only has /bin/sh and /usr/bin/env.
  services.envfs.enable = true;

  # `use flake devbox#node` in a project's .envrc resolves to this exact repo
  # revision, without a clone and without network.
  nix.registry.devbox.flake = devboxFlake;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # Drop the "direnv: loading ..." line printed before every agent command.
    # Errors ("is blocked", nix build failures) are not affected.
    settings.global.log_filter = "^$";
  };

  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      core.excludesFile = "${gitExcludes}";
    };
  };
}
