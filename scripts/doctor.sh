#!/usr/bin/env bash
# Health check. PASS/FAIL lines; never echoes secret values.
#   sudo bash ~/devbox/scripts/doctor.sh
# Overrides: DEVBOX_USER, DEVBOX_PORT
set -uo pipefail

USER_NAME="${DEVBOX_USER:-dev}"
PORT="${DEVBOX_PORT:-4096}"

ok=0; bad=0
pass() { printf 'PASS  %s\n' "$*"; ok=$((ok+1)); }
fail() { printf 'FAIL  %s\n' "$*"; bad=$((bad+1)); }
info() { printf '      %s\n' "$*"; }

SECRETS_FILE="${DEVBOX_SECRETS_FILE:-/var/lib/devbox/secrets.env}"
ENVF=""
[ -r "$SECRETS_FILE" ] && ENVF=$SECRETS_FILE

echo "== system =="
info "$(nixos-version 2>/dev/null || echo 'nixos-version unavailable')"
info "generation $(readlink /nix/var/nix/profiles/system 2>/dev/null | sed -E 's/.*system-//; s/-link$//')"
info "disk: $(df -h / | awk 'NR==2{print $4" free of "$2}')"
info "store: $(du -sh /nix/store 2>/dev/null | cut -f1)"

echo "== secrets =="
if [ -n "$ENVF" ]; then
  pass "credentials env file: $ENVF"
  for k in GITEA_HOST GITEA_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN OPENROUTER_API_KEY OPENCODE_SERVER_PASSWORD; do
    v=$(grep -E "^$k=" "$ENVF" | head -1 | cut -d= -f2-)
    [ -n "$v" ] && info "$k set (${#v} chars)"
  done
else
  info "no $SECRETS_FILE -> no credentials (provider login happens in the UI)"
fi

echo "== login =="
shadow=$(getent shadow "$USER_NAME" 2>/dev/null | cut -d: -f2)
if [ -z "$shadow" ]; then
  fail "no shadow entry for $USER_NAME"
elif [ "$shadow" = "!" ] || [ "${shadow#!}" != "$shadow" ]; then
  info "$USER_NAME has no usable password: key-only login until you run 'passwd'"
else
  pass "$USER_NAME has a password set"
fi

pid=$(systemctl show -p MainPID --value opencode 2>/dev/null)
if [ -n "$ENVF" ] && grep -q '^OPENCODE_SERVER_PASSWORD=.' "$ENVF" \
   && [ -n "$pid" ] && [ "$pid" != "0" ] && [ -r "/proc/$pid/environ" ]; then
  if tr '\0' '\n' < "/proc/$pid/environ" | grep -q '^OPENCODE_SERVER_PASSWORD=.'; then
    pass "running opencode process has OPENCODE_SERVER_PASSWORD"
  else
    fail "running process has no OPENCODE_SERVER_PASSWORD"
    info "  $SECRETS_FILE sets it, but the process predates the file:"
    info "  sudo systemctl restart opencode"
  fi
fi

echo "== config =="
CFG="/home/$USER_NAME/.config/opencode/opencode.json"
[ -e "$CFG" ] && pass "opencode config present" || fail "opencode config missing at $CFG"
[ -L "$CFG" ] && info "-> $(readlink "$CFG")"
for s in gitea github serena; do
  grep -q "\"$s\"" "$CFG" 2>/dev/null && pass "$s server configured" || fail "$s server not in config"
done

[ -e "/home/$USER_NAME/.config/opencode/AGENTS.md" ] && pass "global AGENTS.md present" || fail "global AGENTS.md missing"

echo "== agent environment =="
# The agent's commands inherit the service's environment, not a login shell's.
if [ -n "$pid" ] && [ "$pid" != "0" ] && [ -r "/proc/$pid/environ" ]; then
  if tr '\0' '\n' < "/proc/$pid/environ" | grep -q '^PATH=.*/run/current-system/sw/bin'; then
    pass "service PATH includes the system profile"
  else
    fail "service PATH lacks /run/current-system/sw/bin: the agent will miss tools"
  fi
  if tr '\0' '\n' < "/proc/$pid/environ" | grep -q '^DIRENV_CONFIG=/etc/direnv$'; then
    pass "service sees nix-direnv (DIRENV_CONFIG)"
  else
    fail "service lacks DIRENV_CONFIG: \`use flake\` re-evaluates on every command"
  fi
fi
[ -e /lib64/ld-linux-x86-64.so.2 ] && pass "nix-ld loader present (generic binaries run)" || fail "no /lib64/ld-linux-x86-64.so.2"
/usr/bin/env bash -c true 2>/dev/null && [ -x /bin/bash ] && pass "envfs: /bin/bash resolves" || fail "/bin/bash missing (envfs)"
nix registry list 2>/dev/null | grep -q 'flake:devbox ' && pass "flake registry has devbox" || fail "flake registry lacks devbox"

echo "== binaries =="
# Presence is not enough: a prebuilt binary on NixOS can exist and still refuse
# to start (wrong ELF interpreter). Run each one.
check_bin() {
  local b=$1; shift
  if ! command -v "$b" >/dev/null 2>&1; then
    fail "$b not on PATH"
    return
  fi
  local out ver
  if out=$(timeout 40 "$b" "$@" 2>/dev/null) && [ -n "$out" ]; then
    # banners are multi-line; prefer the line that carries a version
    ver=$(printf '%s\n' "$out" | grep -m1 -E 'v?[0-9]+\.[0-9]+' || true)
    pass "$b ${ver:-ran}"
  elif out=$(timeout 40 "$b" "$@" 2>&1); then
    ver=$(printf '%s\n' "$out" | grep -m1 -E 'v?[0-9]+\.[0-9]+' || true)
    pass "$b ${ver:-ran}"
  else
    fail "$b exists but will not run: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  fi
}
check_bin opencode --version
check_bin gitea-mcp -v
check_bin github-mcp-server --version
if [ -n "${DEVBOX_DOCTOR_OFFLINE:-}" ]; then
  info "serena skipped (DEVBOX_DOCTOR_OFFLINE)"
else
  check_bin serena --version   # first run fetches through uv, may take a minute
fi

echo "== service =="
systemctl is-active --quiet opencode && pass "opencode unit active" || fail "opencode unit: $(systemctl is-active opencode)"
ss -ltn 2>/dev/null | grep -q ":$PORT " && pass "listening on $PORT" || fail "nothing listening on $PORT"
# opencode prints a generated password to the journal; never repeat it here
journalctl -u opencode -n 6 --no-pager 2>/dev/null | sed -E 's/server password .*/server password [redacted]/' | sed 's/^/      /' 

echo "== http surface =="
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:$PORT/api/config")
if [ -n "$ENVF" ] && grep -q '^OPENCODE_SERVER_PASSWORD=.' "$ENVF"; then
  [ "$code" = "401" ] && pass "API rejects unauthenticated requests" || fail "API returned $code without auth - NOT protected"
  set -a; . "$ENVF"; set +a
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -u "opencode:${OPENCODE_SERVER_PASSWORD}" "http://127.0.0.1:$PORT/api/config")
  [ "$code" = "200" ] && pass "API answers 200 as user 'opencode'" || fail "API returned $code as user 'opencode'"
  info "web UI login is username 'opencode', NOT \"$USER_NAME\""

  echo "== forge tokens =="
  if [ -n "${GITEA_TOKEN:-}" ]; then
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Authorization: token $GITEA_TOKEN" "${GITEA_HOST%/}/api/v1/user")
    [ "$code" = "200" ] && pass "Gitea token valid" || fail "Gitea API returned $code"
  fi
  if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" https://api.github.com/user)
    [ "$code" = "200" ] && pass "GitHub token valid" || fail "GitHub API returned $code"
  fi

  echo "== mcp handshake =="
  req='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"doctor","version":"1"}}}'
  out=$(printf '%s\n' "$req" | timeout 25 gitea-mcp -t stdio 2>/dev/null | head -c 400)
  case "$out" in *'"result"'*) pass "gitea-mcp stdio handshake" ;; *) fail "gitea-mcp handshake: ${out:0:120}" ;; esac
else
  # Not a missing feature like an absent token: an unauthenticated /api can run
  # code as the operator, and the service listens on every interface.
  if [ "$code" = "401" ]; then
    # opencode invents a password when OPENCODE_SERVER_PASSWORD is unset: it
    # changes on every start and is printed to the journal, so it is not a
    # usable configuration.
    info "API is locked by an AUTOGENERATED password - it changes on every"
    info "  restart and is written to the journal. Set OPENCODE_SERVER_PASSWORD"
    info "  in $SECRETS_FILE (scripts/secrets-file-init.sh) for a stable one."
  elif [ "$code" = "000" ]; then
    fail "API unreachable - nothing answered on port $PORT (see the service section)"
  elif [ "$code" = "200" ]; then
    fail "API answers 200 WITHOUT auth - anyone who reaches port $PORT can drive the agent"
    info "fix: run scripts/secrets-file-init.sh (a UI password is enough),"
    info "     then: sudo systemctl restart opencode; or stop exposing the port"
  else
    info "API returned $code"
  fi
fi

echo
echo "summary: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
