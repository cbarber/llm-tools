{ pkgs, tools }:

pkgs.mkShell {
  name = "opencode-shell";

  buildInputs =
    with pkgs;
    [
      opencode
      findutils
      bubblewrap
      gh
      tea
    ]
    ++ tools.all;

  shellHook = ''
    export AGENTS_TEMPLATES_DIR="${../templates}"
    export AGENTS_TEMPLATE_DEFAULT="${../templates/default.md}"
    export SETUP_MCP_SCRIPT="${./setup-mcp.sh}"
    export AGENT_SANDBOX_SCRIPT="${../../tools/agent-sandbox.sh}"
    export TOOLS_DIR="${../../tools}"
    export BWRAP_PATH="${pkgs.bubblewrap}/bin/bwrap"
    export OPENCODE_PLUGIN_TEMPER_DIR="${../../.opencode/plugin/temper}"
    export BD_BRANCH="''${BD_BRANCH:-beads-sync}"

    source ${./setup-shell.sh}
  '';
}
