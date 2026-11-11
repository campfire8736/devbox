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
UI=$(ask_secret "Password for the opencode web UI")
[ -n "$UI" ] && printf 'OPENCODE_SERVER_PASSWORD=%s\n' "$UI" >> "$ENVFILE.tmp"

mv "$ENVFILE.tmp" "$ENVFILE"
chmod 600 "$ENVFILE"

echo
echo "wrote $ENVFILE ($(stat -c '%a %U:%G' "$ENVFILE"))"
echo "then:  sudo systemctl restart opencode"
echo "the file is read by systemd only; user $USER_NAME cannot read it."
