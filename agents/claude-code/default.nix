{ pkgs, tools }:

pkgs.mkShell {
  name = "claude-code-shell";

  buildInputs =
    with pkgs;
    [
      claude-code
      findutils
      gh
      tea
    ]
    ++ tools.all;

  shellHook = ''
    export CLAUDECODE=1
    export GIT_SEQUENCE_EDITOR="git-agent-sequence-editor"
    export GIT_EDITOR="git-agent-editor"
    export SETTINGS_TEMPLATE="${./settings.template.json}"
    export SETUP_SETTINGS_SCRIPT="${./setup-settings.sh}"
    export AGENT_SANDBOX_SCRIPT="${../../tools/agent-sandbox.sh}"
    export AGENTS_SKILLS_DIR="${../../agents/skills}"
    export TOOLS_DIR="${../../tools}"
    export FENCE_PATH="${tools.fence}/bin/fence"
    export IRON_PROXY_PATH="${tools.iron-proxy}/bin/iron-proxy"

    source ${./setup-shell.sh}
  '';
}
