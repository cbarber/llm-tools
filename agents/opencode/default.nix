{ pkgs, tools }:

pkgs.mkShell {
  name = "opencode-shell";

  buildInputs =
    with pkgs;
    [
      opencode
      findutils
      bubblewrap
    ]
    ++ tools.all;

  shellHook = ''
    export AGENTS_TEMPLATES_DIR="${../templates}"
    export AGENTS_TEMPLATE_DEFAULT="${../templates/default.md}"
    export SETUP_MCP_SCRIPT="${./setup-mcp.sh}"
    export AGENT_SANDBOX_SCRIPT="${../../tools/agent-sandbox.sh}"
    export COMMON_HELPERS_SCRIPT="${../../tools/common-helpers.sh}"
    export BWRAP_PATH="${pkgs.bubblewrap}/bin/bwrap"

    source ${./setup-shell.sh}
  '';
}
