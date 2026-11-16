# Logging in to the web UI

`opencode serve` binds `0.0.0.0:4096` and serves the API and web UI on one
port. Every `/api/*` call needs either HTTP basic auth (user `opencode`,
password `OPENCODE_SERVER_PASSWORD`) or a session cookie. Unauthenticated
requests get a 401, verified with `POST /api/session`. Reach the port on your
LAN, through a port forward on the host, or over a tailnet such as Tailscale.

A browser, phone included, gets its session cookie from a **pairing link**:

```sh
# on the box: ask the running server for a one-time code
sudo bash -c 'set -eo pipefail; . /var/lib/devbox/secrets.env
  code=$(curl -fsS -u "opencode:$OPENCODE_SERVER_PASSWORD" \
    -X POST http://127.0.0.1:4096/api/pair | jq -r .code)
  ip=$(ip -4 -o addr show scope global | awk "{print \$4}" | cut -d/ -f1 | head -1)
  echo "http://$ip:4096/auth/connect/$code"'
```

Open the printed link in the browser you want to log in. Replace the host and
port if you go through a port forward or a tailnet name. The server checks the
code, sets an `opencode_session_<port>` cookie and redirects to the UI.

- **The link works once and expires after 5 minutes.** Generate a new one for
  each browser. If you open it twice, the second visit says "expired or already
  used".
- **The cookie lasts 30 days** and is `HttpOnly` and `SameSite=Lax`. It's tied
  to the host and port in the link, so pair with the address you'll actually
  use.
- **Sessions are signed with `OPENCODE_SERVER_PASSWORD`.** They survive service
  restarts and rebuilds. Changing the password logs every browser out. Without
  a password in the secrets file, opencode makes up a new one at each start,
  which logs everyone out on every restart. Set one.

**Do not use `opencode pair` on this box.** It only talks to opencode's own
background service, which it finds through `~/.local/state/opencode/service.json`.
Our systemd unit runs plain `opencode serve` and never writes that file, so
`opencode pair` would start a *second* server, with a different port and
password, and print links to that one. (Checked in the 2.2.6 source,
`packages/cli/src/commands/handlers/pair.ts` and `server-process.ts`.)

Avoid the `?auth_token=` query parameter too, even though the server accepts it.
It carries the base64-encoded password in the URL, where it ends up in browser
history.

Plain HTTP is fine on a LAN or tailnet. Put TLS in front before exposing the
port to the internet, because the session cookie travels in clear text.
