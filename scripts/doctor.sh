#!/usr/bin/env bash
# Health check for the devbox. Prints PASS/FAIL lines; never echoes secret values.
# Usage: sudo bash ~/devbox/scripts/doctor.sh
set -uo pipefail

ok=0; bad=0
pass() { printf 'PASS  %s\n' "$*"; ok=$((ok+1)); }
fail() { printf 'FAIL  %s\n' "$*"; bad=$((bad+1)); }
info() { printf '      %s\n' "$*"; }

RENDERED=/run/secrets-rendered/devbox.env
FALLBACK=/var/lib/devbox/secrets.env
ENVF=""
[ -r "$RENDERED" ] && ENVF="$RENDERED"
[ -z "$ENVF" ] && [ -r "$FALLBACK" ] && ENVF="$FALLBACK"

echo "== system =="
info "$(nixos-version 2>/dev/null || echo 'nixos-version unavailable')"
info "generation $(readlink /nix/var/nix/profiles/system | sed 's/.*-//')"
info "disk: $(df -h / | awk 'NR==2{print $4" free of "$2}')"
info "store: $(du -sh /nix/store 2>/dev/null | cut -f1)"

echo "== secrets plumbing =="
if [ -f /var/lib/sops-nix/key.txt ]; then pass "age identity present"; else fail "age identity missing at /var/lib/sops-nix/key.txt"; fi
if [ -n "$ENVF" ]; then pass "env file rendered at $ENVF"; else fail "no rendered env file (sops did not run)"; fi
if [ -n "$ENVF" ]; then
  for k in GITEA_HOST GITEA_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN OPENROUTER_API_KEY OPENCODE_SERVER_PASSWORD; do
    v=$(grep -E "^$k=" "$ENVF" | head -1 | cut -d= -f2-)
    if [ -n "$v" ]; then pass "$k set (${#v} chars)"; else fail "$k empty or missing"; fi
  done
fi

echo "== config =="
CFG=/home/dev/.config/opencode/opencode.json
[ -e "$CFG" ] && pass "opencode config present" || fail "opencode config missing"
[ -L "$CFG" ] && info "-> $(readlink "$CFG")"
for s in gitea github serena; do
  grep -q "\"$s\"" "$CFG" 2>/dev/null && pass "$s server configured" || fail "$s server not in config"
done

echo "== binaries =="
for b in opencode gitea-mcp github-mcp-server serena sops age; do
  if command -v "$b" >/dev/null 2>&1; then pass "$b"; else fail "$b not on PATH"; fi
done
info "$(opencode --version 2>/dev/null | head -1)"

echo "== service =="
if systemctl is-active --quiet opencode; then pass "opencode unit active"; else fail "opencode unit: $(systemctl is-active opencode)"; fi
if ss -ltn 2>/dev/null | grep -q ':4096 '; then pass "listening on 4096"; else fail "nothing listening on 4096"; fi
journalctl -u opencode -n 6 --no-pager 2>/dev/null | sed 's/^/      /'

echo "== http surface =="
if [ -n "$ENVF" ]; then
  set -a; . "$ENVF"; set +a
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1:4096/api/config)
  [ "$code" = "401" ] && pass "API rejects unauthenticated requests (401)" || fail "API returned $code without auth - NOT protected"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -u "opencode:${OPENCODE_SERVER_PASSWORD:-}" http://127.0.0.1:4096/api/config)
  [ "$code" = "200" ] && pass "API answers 200 with auth" || fail "API returned $code with auth"

  echo "== forge tokens =="
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Authorization: token ${GITEA_TOKEN:-}" "${GITEA_HOST:-http://invalid}/api/v1/user")
  [ "$code" = "200" ] && pass "Gitea token valid" || fail "Gitea API returned $code"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN:-}" https://api.github.com/user)
  [ "$code" = "200" ] && pass "GitHub token valid" || fail "GitHub API returned $code"

  echo "== mcp handshake =="
  req='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"doctor","version":"1"}}}'
  out=$(printf '%s\n' "$req" | timeout 25 gitea-mcp -t stdio 2>/dev/null | head -c 400)
  case "$out" in *'"result"'*) pass "gitea-mcp stdio handshake" ;; *) fail "gitea-mcp handshake: ${out:0:120}" ;; esac
fi

echo
echo "summary: $ok passed, $bad failed"
