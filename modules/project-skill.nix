# Creating projects from a chat. opencode's web UI can open folders but not
# create them, so a session at the workspace root asks the agent, and this
# skill tells it exactly how:
#   ~/.claude/skills/devbox-project/  read by Claude Code and by opencode
#                                     (opencode also scans ~/.claude/skills)
#   ~/.config/opencode/commands/new-project.md   `/new-project <url|name> [shell]`
# In Claude Code the skill is also its own command: `/devbox-project`.
{ config, pkgs, ... }:
let
  cfg = config.devbox;
  ws = cfg.workspaceDir;
  home = "/home/${cfg.user}";

  skill = pkgs.writeTextDir "devbox-project/SKILL.md" ''
    ---
    name: devbox-project
    description: Create, clone or migrate a project in ${ws} with the devbox layout and its environment. Use when the user asks to clone a repository, start or create a new project, set up a repo to work on, or move an old project that has a src/ folder.
    ---

    # Setting up a devbox project

    Projects live in `${ws}/<name>/`: the checkout in `<name>/<name>/`, its
    environment in `<name>/.envrc` (outside git), worktrees in `<name>/wt/`.
    `devbox-project` creates all of it. **Never create these folders, clone,
    or write the `.envrc` by hand.** Run the commands below from `${ws}`.

    ## 1. What to create

    - A git URL (or "owner/repo", meaning `https://github.com/owner/repo`):
      `devbox-project init <url> [shell]`. The project is named after the repo.
    - A name for something new: `devbox-project new <name> [shell]`, an empty
      git repo.
    - An existing project with a `src/` folder:
      `devbox-project migrate <name>`. It moves `src/` to `<name>/`, repairs
      the worktrees and updates the `.envrc`. Then go to step 4.

    If the request gives neither a URL nor a name, ask for one.

    ## 2. Pick the environment (`shell`)

    `base` (system libraries only), `node`, `python`, `rust`, `go`, `upstream`
    (the repo's own `flake.nix`), `none`. Use the one the user named. For a
    clone where the user named none, clone with `base`, then look at the
    checkout's top level:

    | found | shell |
    | --- | --- |
    | `flake.nix` with a `devShells` output | `upstream` |
    | `package.json` | `node` |
    | `pyproject.toml`, `setup.py`, `requirements*.txt` | `python` |
    | `Cargo.toml` | `rust` |
    | `go.mod` | `go` |

    If one matches, write that line to `${ws}/<name>/.envrc`
    (`use flake devbox#<shell>`, or `use flake ./<name>` for upstream) and run
    `direnv allow ${ws}/<name>`. If several languages are needed, keep `base`
    and follow "Getting a toolchain" in your global instructions instead.

    ## 3. Check it

    Run `git status` and the toolchain's version command (`node --version`,
    `python3 --version`, ...) **with the shell's working directory set to**
    `${ws}/<name>/<name>`. The first command there builds the environment and
    can take a minute or two; later ones are cached. A "blocked" error means
    `direnv allow ${ws}/<name>` was not run.

    ## 4. Hand over

    Tell the user the path and the environment, then:

    - opencode web UI: open `${ws}/<name>/<name>` as a project. The project
      only gets its name, git view, workspaces (worktrees) and own
      `AGENTS.md` there, not in this `${ws}` session.
    - Claude Code or agy over SSH: start it in `${ws}/<name>/<name>`.

    Do not start on the task itself in the `${ws}` session unless the user
    asks you to.
  '';

  command = pkgs.writeText "new-project.md" ''
    ---
    description: Create or clone a devbox project (git URL or name, optional shell)
    ---
    Set up a devbox project by following the `devbox-project` skill.
    Request: $ARGUMENTS
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${home}/.claude 0700 ${cfg.user} users -"
    "d ${home}/.claude/skills 0755 ${cfg.user} users -"
    "L+ ${home}/.claude/skills/devbox-project - - - - ${skill}/devbox-project"
    "d ${home}/.config/opencode/commands 0755 ${cfg.user} users -"
    "L+ ${home}/.config/opencode/commands/new-project.md - - - - ${command}"
  ];
}
