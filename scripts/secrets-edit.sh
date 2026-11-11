#!/usr/bin/env bash
# Edit the committed secrets as user `dev`. Decrypts with the host key, re-encrypts
# on save, and reminds you to rebuild.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops secrets/secrets.yaml
echo
echo "edited. now:  git add secrets/secrets.yaml && git commit -m 'secrets: update' && sudo nixos-rebuild switch --flake .#devbox"
