{ pkgs, tools }:

pkgs.mkShell {
  name = "claude-code-shell";

  buildInputs =
    with pkgs;
    [
      claude-code
      findutils
    ]
    ++ tools.all;

  shellHook = ''
    export CLAUDE_TEMPLATE="${./claude.template.md}"
    export SETTINGS_TEMPLATE="${./settings.template.json}"
    export SETUP_MCP_SCRIPT="${./setup-mcp.sh}"
    export SETUP_SETTINGS_SCRIPT="${./setup-settings.sh}"

    source ${./setup-shell.sh}
  '';
}
