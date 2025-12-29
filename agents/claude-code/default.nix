{ pkgs, tools }:

pkgs.mkShell {
  name = "claude-code-shell";

  buildInputs =
    with pkgs;
    [
      claude-code
      findutils
      bubblewrap
    ]
    ++ tools.all;

  shellHook = ''
    export AGENTS_TEMPLATES_DIR="${../templates}"
    export AGENTS_TEMPLATE_DEFAULT="${../templates/default.md}"
    export SETTINGS_TEMPLATE="${./settings.template.json}"
    export SETUP_MCP_SCRIPT="${./setup-mcp.sh}"
    export SETUP_SETTINGS_SCRIPT="${./setup-settings.sh}"
    export AGENT_SANDBOX_SCRIPT="${../../tools/agent-sandbox.sh}"
    export TOOLS_DIR="${../../tools}"
    export BWRAP_PATH="${pkgs.bubblewrap}/bin/bwrap"

    source ${./setup-shell.sh}
  '';
}
