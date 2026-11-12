{ config, lib, pkgs, ... }:
let
  cfg = config.devbox;
in
{
  config = lib.mkIf cfg.docker.enable {
    virtualisation.docker.enable = true;

    # Pruning is deliberately manual. `--all` would evict the base images that
    # test suites pull on every run; watching `docker system df` is cheaper than
    # re-downloading them.
    virtualisation.docker.autoPrune.enable = false;

    # Membership of `docker` is root-equivalent. It adds no privilege the
    # operator does not already have through sudo, but it does make "run this
    # public image" a single command.
    users.users.${cfg.user}.extraGroups = [ "docker" ];

    environment.systemPackages = [ pkgs.docker-compose ];

    # The plugin form (`docker compose`) resolves docker-<name> from here; the
    # standalone binary alone would only give `docker-compose`.
    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.docker 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.docker/cli-plugins 0755 ${cfg.user} users -"
      "L+ /home/${cfg.user}/.docker/cli-plugins/docker-compose - - - - ${pkgs.docker-compose}/bin/docker-compose"
    ];
  };
}
