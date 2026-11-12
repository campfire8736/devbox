#!/usr/bin/env bash
# `devbox.secrets = "file"`: write the credentials env file on the box.
# Run as root. Nothing secret is committed anywhere.
set -euo pipefail

ENVFILE="${DEVBOX_SECRETS_FILE:-/var/lib/devbox/secrets.env}"
USER_NAME="${DEVBOX_USER:-dev}"

ask() { local v; read -r -p "$1: " v; printf '%s' "$v"; }
ask_secret() { local v; read -r -s -p "$1: " v; echo >&2; printf '%s' "$v"; }

umask 077
install -d -m 750 "$(dirname "$ENVFILE")"

: > "$ENVFILE.tmp"
chmod 600 "$ENVFILE.tmp"

GITEA_HOST=$(ask "Gitea URL as seen from this machine (blank to skip)")
if [ -n "$GITEA_HOST" ]; then
  printf 'GITEA_HOST=%s\n' "$GITEA_HOST" >> "$ENVFILE.tmp"
  printf 'GITEA_TOKEN=%s\n' "$(ask_secret "Gitea token")" >> "$ENVFILE.tmp"
fi
GH=$(ask_secret "GitHub read-only token (blank to skip)")
[ -n "$GH" ] && printf 'GITHUB_PERSONAL_ACCESS_TOKEN=%s\n' "$GH" >> "$ENVFILE.tmp"
OR=$(ask_secret "OpenRouter API key (blank to skip)")
[ -n "$OR" ] && printf 'OPENROUTER_API_KEY=%s\n' "$OR" >> "$ENVFILE.tmp"
while :; do
  UI=$(ask_secret "Password for the opencode web UI (required)")
  [ -n "$UI" ] && break
  echo "  required: without it opencode invents a new password on every restart" >&2
done
printf 'OPENCODE_SERVER_PASSWORD=%s\n' "$UI" >> "$ENVFILE.tmp"

mv "$ENVFILE.tmp" "$ENVFILE"
chmod 600 "$ENVFILE"

echo
echo "wrote $ENVFILE ($(stat -c '%a %U:%G' "$ENVFILE"))"
echo
echo "Web UI login:  username  opencode   (NOT \"$USER_NAME\" - that is the Unix account)"
echo "               password  the one you just typed"
echo
# Writing the file is not enough: the unit only loads it when the option says so.
mode=$( cd "$REPO_ROOT" && nix eval --raw .#nixosConfigurations.devbox.config.devbox.secrets 2>/dev/null || echo unknown )
if [ "$mode" != "file" ]; then
  echo "WARNING: devbox.secrets is currently \"$mode\", not \"file\"."
  echo "  The opencode unit only loads this file in \"file\" mode. Set"
  echo "  secrets = \"file\" in hosts/devbox/default.nix, commit, then:"
  echo "      sudo nixos-rebuild switch --flake ~/devbox#devbox"
  echo "  'systemctl restart opencode' alone will NOT pick it up."
else
  echo "mode is \"file\". If the service predates this file:"
  echo "      sudo systemctl restart opencode"
fi
