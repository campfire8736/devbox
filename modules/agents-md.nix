# Global instructions for the agents, one variant per tool:
#   opencode  ~/.config/opencode/AGENTS.md
#   claude    ~/.claude/CLAUDE.md imports /etc/devbox/agents/claude.md
#   agy       ~/.gemini/AGENTS.md
# Everything here is something the agent would otherwise rediscover, wrongly,
# on every task: it is trained on Ubuntu, and this is not Ubuntu. Only "Where
# commands run" differs, because each tool runs shell commands differently.
{ cfg, tool }:
let
  ws = cfg.workspaceDir;

  whereCommandsRun = {
    # opencode: every command is a fresh `agent-shell -c`, started in the tool's
    # workdir (the session directory by default).
    opencode = ''
      Every shell command you run is executed inside the environment of the nearest
      `.envrc` **above the git checkout**, so all worktrees share it. Each command is
      a fresh process: `cd`, `export` and `nix shell` do not carry over to the next
      one. To change the environment, edit that `.envrc` and run
      `direnv allow ${ws}/<name>`.

      Your session may be opened at the workspace root (`${ws}`), not inside a
      project. That is how new projects get created or cloned. From there:

      - **Set the shell tool's `workdir`** to the project folder
        (`${ws}/<name>/<name>`, or a worktree) instead of writing
        `cd <dir> && <command>`. The environment is chosen from where the command
        starts. A command that *begins* with `cd <dir> &&` is recognised, but a `cd`
        later in the command is not, and the command then runs without the project's
        toolchain.
      - When the project is set up, suggest that the user open
        `${ws}/<name>/<name>` as a project in the web UI: the project's own
        `AGENTS.md`, its git view and its workspaces only work there.
    '';

    # Claude Code: the working directory persists; a SessionStart/CwdChanged
    # hook loads the environment of the new directory for the commands after it.
    claude = ''
      Your working directory persists between Bash commands. When it changes, a
      hook loads the environment of the new directory: the nearest `.envrc`
      **above the git checkout**, so all worktrees share it. That environment
      applies from the **next** command on:

      - `cd` into the project (`${ws}/<name>/<name>`, or a worktree) in a command of
        its own, then build or test in the following commands. In
        `cd <dir> && make test` the `make` runs before the hook, without the
        project's toolchain.
      - After editing the `.envrc` (and `direnv allow ${ws}/<name>`), the new
        environment loads at the next directory change. Until then, or for one
        command in another project without moving, use
        `agent-shell -c '<command>'`: it loads the environment of the directory it
        starts in, on every call.

      If the session started at the workspace root (`${ws}`), the project's
      instruction files at its root may not be loaded; suggest that the user
      start `claude` in `${ws}/<name>/<name>` once it is set up.
    '';

    # agy: no hook mechanism; its commands inherit the environment it was
    # started in (the `agy` wrapper resolves it from the launch directory).
    agy = ''
      Your commands run in the environment of the directory `agy` was **started
      from**: the nearest `.envrc` above that git checkout. Changing directory
      during the session does not change it.

      - Run project commands from that project. For another project, or after
        editing an `.envrc` (and `direnv allow ${ws}/<name>`), wrap the command:
        `cd ${ws}/<other>/<other> && agent-shell -c '<command>'`. `agent-shell`
        loads the environment of the directory it starts in.
      - If you were started at the workspace root (`${ws}`) to create or clone a
        project, suggest that the user restart `agy` in `${ws}/<name>/<name>`
        once it is set up: its environment and its own `AGENTS.md` load
        from there.
    '';
  }.${tool};
in
''
  # This machine

  You are running on **NixOS**, inside a VM that exists for you. You have
  passwordless `sudo`. There is **no `apt`, `dnf` or `brew`**, and
  `nix-env -i` / `nix profile install` are the wrong answer too: the system is
  rebuilt from a git repo and anything installed that way is invisible to it.

  ## Projects live in `${ws}/<name>/`

  ```
  ${ws}/<name>/
    .envrc          the project's environment. NOT in git. Yours to edit.
    <name>/         the git checkout. Never add environment files here.
    wt/<branch>/    git worktrees (`git -C <name> worktree add ../wt/<branch>`)
  ```

  Create projects only with `devbox-project`, never by hand: follow the
  `devbox-project` skill. In short, `devbox-project init <git-url> [shell]`
  clones, `devbox-project new <name> [shell]` starts an empty repo
  (shell: `base`, `node`, `python`, `rust`, `go`, `upstream`, `none`).
  Projects made before this layout have `src/` instead of `<name>/`;
  `devbox-project migrate <name>` moves them.

  ## Where commands run

  ${whereCommandsRun}
  ## Serena (code navigation)

  The `serena` MCP server answers symbol-level questions through real language
  servers: find a symbol, its references, its callers, a file's outline. It also
  has symbol-aware edits. Prefer it over grep to navigate code you don't know.
  Its index never goes stale because it asks the language server directly.

  - It picks its project from the session's directory: the nearest folder with
    `.git` or `.serena/project.yml`. In a session at `${ws}` there
    is none, so call its `activate_project` tool with the checkout's path
    (or a worktree path) first.
  - It creates a `.serena/` folder in the project root (`project.yml`, memories,
    caches, logs). That is expected and is serena's working data. **Never commit
    `.serena/`**: it is excluded from git on this machine, so do not force-add it.

  ## Getting a toolchain

  1. Read the project's own declarations first: CI workflow files, `.nvmrc`,
     `.python-version`, `.tool-versions`, `rust-toolchain.toml`, `go.mod`,
     `.devcontainer/`.
  2. The shared environments (`use flake devbox#node` etc.) carry the system
     libraries (`pkg-config`, `openssl`, `zlib`, `libffi`, `sqlite`, `gcc`,
     `make`). Version managers are installed and work here: `mise`, `uv`,
     `rustup`, `corepack`. Use them to match the version the project asks for.
  3. A missing library or tool (what `apt install libfoo-dev` would give):
     write a `flake.nix` next to the `.envrc` (not in the checkout), change `.envrc`
     to `use flake .`, and `direnv allow` it:

     ```nix
     {
       inputs.devbox.url = "devbox";
       outputs = { devbox, ... }:
         let pkgs = devbox.inputs.nixpkgs.legacyPackages.x86_64-linux; in {
           devShells.x86_64-linux.default = pkgs.mkShell {
             inputsFrom = [ devbox.devShells.x86_64-linux.node ];
             packages = [ pkgs.postgresql ];
           };
         };
     }
     ```

     Find package names with `nix search nixpkgs <name>`. A one-off command can
     use `nix shell nixpkgs#<pkg> --command ...`, but that does not set
     `PKG_CONFIG_PATH` or include paths; use the flake for build dependencies.
  4. If the upstream repo ships its own `flake.nix`, use it: `use flake ./<name>`
     in the parent `.envrc`.
  5. If the project is built around a devcontainer or Docker
     (`.devcontainer/`, `docker compose` in CONTRIBUTING), use that instead:
     `devcontainer up --workspace-folder <name>`, then `devcontainer exec ...`.

  Prebuilt Linux binaries (npm native modules, pip wheels, downloaded release
  tarballs, `#!/bin/bash` scripts) work here through `nix-ld` and `envfs`. If one
  still fails with "cannot run dynamically linked executables" or a missing
  `.so`, say so instead of working around it with `patchelf`.

  ## Services

  Databases, caches and queues for tests come from Docker:
  `docker compose up -d` or `docker run`. Do not try to install them on the host.

  ## Git

  - Never commit `.envrc`, `.direnv/`, or a `flake.nix`/`flake.lock` you created.
    They live outside the checkout for that reason.
  - Work on a branch in a worktree. Commit there.
  - You cannot push to GitHub: the token is read-only. Finish with a local
    branch and a summary of what changed and how you verified it.
''
