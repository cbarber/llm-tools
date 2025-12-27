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
    # Source .env files if they exist (for API key auth)
    [ -f .env ] && source .env
    [ -f ~/.config/opencode/.env ] && source ~/.config/opencode/.env

    # Note: OpenCode supports API key authentication
    # Set ANTHROPIC_API_KEY in .env or ~/.config/opencode/.env
    if [ -z "$ANTHROPIC_API_KEY" ]; then
      echo "Note: No ANTHROPIC_API_KEY found. Set it for API key authentication."
      echo "Set ANTHROPIC_API_KEY in .env or ~/.config/opencode/.env"
    fi

    # Setup MCP configuration for detected languages
    ${./setup-mcp.sh}

    # Auto-launch opencode unless disabled
    if [[ "''${AUTO_LAUNCH:-true}" == "true" ]]; then
      exec opencode
    else
      echo "OpenCode environment ready. Run 'opencode' to start."
      echo "Available commands: cclsp, smart-lint, smart-test, notify"
    fi
  '';
}
