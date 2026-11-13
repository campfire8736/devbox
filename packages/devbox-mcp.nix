{ lib, writeShellApplication, gitea-mcp, github-mcp-server, secretsFile }:
# One launcher per MCP server, shared by every agent on the box (opencode,
# Claude Code, agy). Each launcher reads the devbox secrets file itself, so the
# servers get their tokens however the agent was started: from the systemd
# unit, or from an SSH shell in tmux.
#
# The file is parsed, not sourced: KEY=value lines, optional surrounding
# quotes, `#` comments. That is the subset systemd's EnvironmentFile= and
# scripts/secrets-file-init.sh agree on.
let
  loadSecrets = ''
    if [ -r ${lib.escapeShellArg secretsFile} ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ""|"#"*) continue ;; esac
        key="''${line%%=*}"
        value="''${line#*=}"
        case "$value" in
          \"*\") value="''${value:1:''${#value}-2}" ;;
          \'*\') value="''${value:1:''${#value}-2}" ;;
        esac
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && export "$key=$value"
      done < ${lib.escapeShellArg secretsFile}
    fi
  '';

  launcher = name: text: writeShellApplication {
    name = "devbox-mcp-${name}";
    text = loadSecrets + text;
  };
in
{
  gitea = launcher "gitea" ''
    export GITEA_HOST="''${GITEA_HOST:-}"
    export GITEA_ACCESS_TOKEN="''${GITEA_TOKEN:-}"
    export GITEA_SCOPES="repository,file,branch,issue,pull_request,project,wiki,search"
    exec ${lib.getExe gitea-mcp} -t stdio "$@"
  '';

  # read-only, and limited to what OSS research needs
  github = launcher "github" ''
    export GITHUB_PERSONAL_ACCESS_TOKEN="''${GITHUB_PERSONAL_ACCESS_TOKEN:-}"
    exec ${lib.getExe github-mcp-server} stdio --read-only --toolsets repos,issues,pull_requests "$@"
  '';
}
