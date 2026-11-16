# Projects

## Layout

A public repo almost never ships a Nix environment, and its env files must not
end up in a PR. So the environment lives **next to** the checkout, not in it:

```
/srv/work/<name>/
  .envrc          use flake devbox#node    ← not in any git repo
  <name>/         the git checkout, untouched
  wt/<branch>/    git worktrees, which share the same env
```

The checkout folder carries the project's name because opencode names a
project after that folder.

## Creating a project

The web UI can open folders but not create them. So open a session at
`/srv/work` and either ask ("clone owner/repo", "start a new project foo") or
type:

```
/new-project <git-url-or-name> [shell]
```

Both go through the `devbox-project` skill
(`~/.claude/skills/devbox-project/`, which opencode and Claude Code both read;
in Claude Code it is also `/devbox-project`). The agent runs `devbox-project`,
picks the environment from the repo's files when you don't name one, checks
that it builds, and tells you which folder to open.

The helper itself, for a shell:

```sh
devbox-project init https://github.com/owner/repo node   # clone
devbox-project new foo python                            # empty repo
devbox-project migrate foo                               # old foo/src layout -> foo/foo
```

`shell` is one of `base`, `node`, `python`, `rust`, `go`, `upstream` (the
repo's own `flake.nix`) or `none`.

**Migrating from the `src/` layout.** Projects created before the checkout was
named after the project have `<name>/src/`. `migrate` moves it, repairs its
worktrees (wherever they are) and updates a `use flake ./src` in the
`.envrc`. Sessions opened in the old `src/` path keep their history but point
to a folder that no longer exists.

## Opening it in the web UI

**Open `/srv/work/<name>/<name>` as the project**, not `/srv/work/<name>`.
opencode recognises a project by its git checkout (keyed by the remote), and
the parent folder is not one: opened there, it lands in opencode's catch-all
"global" project, with no git view, no workspaces, and the repo's own
`AGENTS.md` unread. The environment is unaffected either way, since the parent
`.envrc` is found from the checkout. Sessions started at `/srv/work` are still
the place to create or clone projects.

## Worktrees

Worktrees are extra checkouts of the same repo on other branches: one per
issue, so parallel sessions don't switch branches under each other.

- **Web UI:** "New workspace" creates one. The generated `opencode.json` sets
  `worktree.directory = "../wt"`, resolved from the main checkout, so it lands
  in `/srv/work/<name>/wt/<workspace>` and shares the project's environment.
  opencode shows it under the same project.
- **Shell or agent:** `git -C <name> worktree add ../wt/<branch>` does the
  same.

A repo cloned straight to `/srv/work/<repo>`, without `devbox-project`, would
put its worktrees in a shared `/srv/work/wt/`. Use the layout.

## How a command picks its environment

opencode's `shell` is set once, globally, to `agent-shell`. opencode runs every
command as `<shell> -c "<command>"` with cwd set to the project
(`packages/core/src/shell/select.ts` at v2.2.6), and the wrapper picks the
environment:

| found | dispatch |
| --- | --- |
| a `.envrc` **above** the git checkout | `direnv exec <that dir>` — the devbox layout above |
| otherwise the nearest `.envrc` / `flake.nix` from cwd up | `direnv exec` / `nix develop` — what the repo ships itself |
| neither | plain `bash -c` |

The parent `.envrc` wins, so the box stays in control of what runs, and it can
still use an upstream flake with `use flake ./<name>`
(`devbox-project init … upstream`). `direnv allow` happens once per project,
not per worktree.

"cwd" is the shell tool's working directory, or the target of a leading
`cd <dir> &&` in the command. That second case covers sessions opened at
`/srv/work`: there the tool starts in the workspace root, and agents write
`cd /srv/work/foo/foo && make test` rather than setting the tool's `workdir`.
A `cd` later in the command is not recognised, so the agents' instructions
tell them to use `workdir`.

Claude Code and the Antigravity CLI (`agy`) get the same environment by their own mechanisms; see
[terminal-agents.md](terminal-agents.md).

Serena picks its project the same way, from the session's directory. In a
`/srv/work` session it has none until the agent calls `activate_project`. It
keeps per-project data in `<project>/.serena/`, which the global git excludes
file keeps out of commits.

## Shared environments and generic binaries

`devbox#<shell>` is this repo's `devShells` (`shells.nix`), resolved through
the system flake registry, so it is pinned to the deployed revision and needs
no clone. The shells carry system libraries (pkg-config, openssl, zlib,
libffi, sqlite, gcc, make); the toolchain version comes from the project's own
`.nvmrc`, `.python-version` or `rust-toolchain.toml`, through corepack, uv,
mise and rustup. A project that needs more gets a `flake.nix` next to its
`.envrc`.

Beyond Nix environments, the box accepts generic Linux habits:

- `nix-ld` runs prebuilt binaries: npm native modules, wheels, rustup/mise
  toolchains, release tarballs;
- `envfs` resolves `#!/bin/bash` and `/usr/bin/python3`;
- Docker runs test services;
- `devcontainer` covers projects built around `.devcontainer/`.

## What the agents are told

All of this is in the agents' global instructions, generated by
`modules/agents-md.nix` (for opencode, `~/.config/opencode/AGENTS.md`). A
project's own `AGENTS.md` adds to it, and a project-level `opencode.json` or
`.opencode/` can still override `shell`, add MCP servers or set permissions.
