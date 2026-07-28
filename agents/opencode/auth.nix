{ pkgs }:

pkgs.mkShell {
  name = "opencode-auth-shell";
  packages = [ pkgs.opencode ];

  shellHook = ''
    unset OPENCODE_AUTH_CONTENT IN_AGENT_SANDBOX
  '';
}
