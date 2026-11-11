#!/usr/bin/env bash
# Run this ONCE, inside a clone of this repo, before installing NixOS.
# Creates an age identity, collects the secrets interactively, encrypts them,
# and commits the ciphertext. Values are typed here and never leave the box in
# plaintext -- except that you must back up the age identity yourself.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="$REPO_ROOT/secrets"
AGE_KEY="$SECRETS_DIR/devbox.agekey"
ENVFILE="$SECRETS_DIR/secrets.yaml"

if ! command -v age-keygen >/dev/null 2>&1 || ! command -v sops >/dev/null 2>&1; then
  echo ">> age/sops missing, fetching them through nix"
  export NIX_CONFIG="experimental-features = nix-command flakes"
  exec nix shell nixpkgs#age nixpkgs#sops -c bash "${BASH_SOURCE[0]}" "$@"
fi

mkdir -p "$SECRETS_DIR"
if [ -f "$AGE_KEY" ]; then
  echo ">> reusing existing age identity at $AGE_KEY"
else
  umask 077
  age-keygen -o "$AGE_KEY" 2>/dev/null
  echo ">> generated age identity at $AGE_KEY"
fi
PUB="$(age-keygen -y "$AGE_KEY")"

cat > "$REPO_ROOT/.sops.yaml" <<EOF
# Encrypts only secrets/secrets.yaml; the public key below is safe to commit.
creation_rules:
  - path_regex: secrets/secrets\\.yaml$
    age: $PUB
EOF

ask() { local v; read -r -p "$1: " v; printf '%s' "$v"; }
ask_secret() { local v; read -r -s -p "$1: " v; echo >&2; printf '%s' "$v"; }
quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"; }

echo
echo "== values (input is not echoed for secrets) =="
GITEA_HOST=$(ask "Gitea URL as seen from the VM (e.g. http://gitea.local:8085)")
GITEA_TOKEN=$(ask_secret "Gitea token for the devbox")
GITHUB_PAT=$(ask_secret "GitHub fine-grained token (read-only)")
OPENROUTER_KEY=$(ask_secret "OpenRouter API key")
UI_PASS=$(ask_secret "Password for the opencode web UI")

echo
while :; do
  P1=$(ask_secret "Login password for user dev")
  P2=$(ask_secret "Repeat it")
  [ "$P1" = "$P2" ] && break
  echo "  mismatch, try again" >&2
done
HASH=$(printf '%s' "$P1" | openssl passwd -6 -stdin)

umask 077
cat > "$ENVFILE" <<EOF
dev_password_hash: $(quote "$HASH")
GITEA_HOST: $(quote "$GITEA_HOST")
GITEA_TOKEN: $(quote "$GITEA_TOKEN")
GITHUB_PERSONAL_ACCESS_TOKEN: $(quote "$GITHUB_PAT")
OPENROUTER_API_KEY: $(quote "$OPENROUTER_KEY")
OPENCODE_SERVER_PASSWORD: $(quote "$UI_PASS")
EOF

sops --encrypt --in-place "$ENVFILE"
unset P1 P2 HASH GITEA_TOKEN GITHUB_PAT OPENROUTER_KEY UI_PASS

echo
echo "== encrypted =="
head -1 "$ENVFILE" >/dev/null && echo "   $ENVFILE written"

cd "$REPO_ROOT"
git add .sops.yaml secrets/secrets.yaml
git -c user.name="${GIT_USER_NAME:-devbox}" -c user.email="${GIT_USER_EMAIL:-devbox@localhost}" \
  commit -m "secrets: add encrypted devbox secrets" --quiet || echo "   (nothing new to commit)"
echo "   committing succeeded; push it with:  git push"

cat <<EOF

============================================================================
BACK THIS UP NOW -- without it the secrets are unrecoverable:

    $AGE_KEY

Copy it into your password manager or an offline location. It is gitignored.

Then install:

    sudo nix --extra-experimental-features 'nix-command flakes' \\
      run github:nix-community/disko -- --mode disko ./hosts/devbox/disko.nix
    sudo install -Dm600 secrets/devbox.agekey /mnt/var/lib/sops-nix/key.txt
    sudo nixos-install --flake .#devbox --no-root-password
    reboot

The second command is what lets the VM decrypt its own secrets on first boot.
============================================================================
EOF
