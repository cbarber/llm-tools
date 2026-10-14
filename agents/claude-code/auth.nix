{ pkgs }:

pkgs.mkShell {
  name = "claude-code-auth-shell";
  packages = [ pkgs.claude-code ];

  shellHook = ''
    unset CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_REFRESH_TOKEN CLAUDE_CODE_OAUTH_SCOPES
    unset IN_AGENT_SANDBOX
  '';
}
