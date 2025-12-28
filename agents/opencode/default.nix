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
    export SETUP_MCP_SCRIPT="${./setup-mcp.sh}"

    source ${./setup-shell.sh}
  '';
}
