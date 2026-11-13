# Global instructions for the agent, installed as ~/.config/opencode/AGENTS.md.
# Everything here is something the agent would otherwise rediscover, wrongly,
# on every task: it is trained on Ubuntu, and this is not Ubuntu.
{ cfg }:
''
  # This machine

  You are running on **NixOS**, inside a VM that exists for you. You have
  passwordless `sudo`. There is **no `apt`, `dnf` or `brew`**, and
  `nix-env -i` / `nix profile install` are the wrong answer too: the system is
  rebuilt from a git repo and anything installed that way is invisible to it.

  ## Projects live in `${cfg.workspaceDir}/<name>/`

  ```
  ${cfg.workspaceDir}/<name>/
    .envrc          the project's environment. NOT in git. Yours to edit.
    src/            the upstream clone. Never add environment files here.
    wt/<branch>/    git worktrees (`git -C src worktree add ../wt/<branch>`)
  ```

  Start a new one with `devbox-project init <git-url> [base|node|python|rust|go]`.

  Every shell command you run is executed inside the environment of the nearest
  `.envrc` **above the git checkout**, so all worktrees share it. Each command is
  a fresh process: `cd`, `export` and `nix shell` do not carry over to the next
  one. To change the environment, edit that `.envrc` and run
  `direnv allow ${cfg.workspaceDir}/<name>`.

  ## Where commands run

  Your session may be opened at the workspace root (`${cfg.workspaceDir}`), not
  inside a project. That is how new projects get created or cloned. From there:

  - **Set the shell tool's `workdir`** to the project folder
    (`${cfg.workspaceDir}/<name>/src`, or a worktree) instead of writing
    `cd <dir> && <command>`. The environment is chosen from where the command
    starts. A command that *begins* with `cd <dir> &&` is recognised, but a `cd`
    later in the command is not, and the command then runs without the project's
    toolchain.
  - **Activate the project in Serena** (below) before using its tools.
  - When the project is set up, suggest that the user open a session in its
    `src/` folder: the project's own `AGENTS.md` is only read there.

  ## Serena (code navigation)

  The `serena` MCP server answers symbol-level questions through real language
  servers: find a symbol, its references, its callers, a file's outline. It also
  has symbol-aware edits. Prefer it over grep to navigate code you don't know.
  Its index never goes stale because it asks the language server directly.

  - It picks its project from the session's directory: the nearest folder with
    `.git` or `.serena/project.yml`. In a session at `${cfg.workspaceDir}` there
    is none, so call its `activate_project` tool with the project's `src/` path
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
     write a `flake.nix` next to the `.envrc` (not in `src/`), change `.envrc`
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
  4. If the upstream repo ships its own `flake.nix`, use it: `use flake ./src`
     in the parent `.envrc`.
  5. If the project is built around a devcontainer or Docker
     (`.devcontainer/`, `docker compose` in CONTRIBUTING), use that instead:
     `devcontainer up --workspace-folder src`, then `devcontainer exec ...`.

  Prebuilt Linux binaries (npm native modules, pip wheels, downloaded release
  tarballs, `#!/bin/bash` scripts) work here through `nix-ld` and `envfs`. If one
  still fails with "cannot run dynamically linked executables" or a missing
  `.so`, say so instead of working around it with `patchelf`.

  ## Services

  Databases, caches and queues for tests come from Docker:
  `docker compose up -d` or `docker run`. Do not try to install them on the host.

  ## Git

  - Never commit `.envrc`, `.direnv/`, or a `flake.nix`/`flake.lock` you created.
    They live outside `src/` for that reason.
  - Work on a branch in a worktree. Commit there.
  - You cannot push to GitHub: the token is read-only. Finish with a local
    branch and a summary of what changed and how you verified it.
''
