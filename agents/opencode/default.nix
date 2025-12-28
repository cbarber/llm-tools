{ pkgs, tools }:

pkgs.mkShell {
  name = "opencode-shell";

  buildInputs =
    with pkgs;
    [
      opencode
      findutils
    ]
    ++ tools.all;

  shellHook = ''
    export AGENTS_TEMPLATES_DIR="${../templates}"
    export AGENTS_TEMPLATE_DEFAULT="${../templates/default.md}"
    export SETUP_MCP_SCRIPT="${./setup-mcp.sh}"

    source ${./setup-shell.sh}
  '';
}
