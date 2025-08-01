{ pkgs, tools }:

pkgs.mkShell {
  name = "claude-code-shell";
  
  buildInputs = with pkgs; [
    claude-code
    findutils
  ] ++ tools.all;

  shellHook = ''
    export CLAUDE_TEMPLATE="${./claude.template.md}"
    export SETTINGS_TEMPLATE="${./settings.template.json}"

    # Source .env files if they exist (for API key auth)
    [ -f .env ] && source .env
    [ -f ~/.config/claude/.env ] && source ~/.config/claude/.env

    # Note: Claude Code supports both browser auth and API key
    # If no API key is set, it will attempt browser authentication
    if [ -z "$ANTHROPIC_API_KEY" ]; then
      echo "Note: No ANTHROPIC_API_KEY found. Claude Code will use browser authentication."
      echo "If you prefer API key auth, set ANTHROPIC_API_KEY in .env or ~/.config/claude/.env"
    fi

    # Check for CLAUDE files in all locations Claude searches
    claude_found=false

    # Check current and parent directories (walk up to root)
    dir="$(pwd)"
    while [ "$dir" != "/" ]; do
      if [ -f "$dir/CLAUDE.md" ] || [ -f "$dir/CLAUDE.local.md" ]; then
        claude_found=true
        break
      fi
      dir="$(dirname "$dir")"
    done

    # Check child directories using find
    if [ "$claude_found" = false ] && find . -name "CLAUDE.md" -o -name "CLAUDE.local.md" | head -1 | grep -q .; then
      claude_found=true
    fi

    # Check home directory
    [ "$claude_found" = false ] && [ -f ~/.claude/CLAUDE.md ] && claude_found=true

    # Create template if no CLAUDE file found anywhere
    if [ "$claude_found" = false ]; then
      cp "$CLAUDE_TEMPLATE" ./CLAUDE.local.md
      echo "Created CLAUDE.local.md from template (add to .gitignore)"
    fi

    # Setup MCP configuration for detected languages
    ${./setup-mcp.sh}

    # Setup Claude Code hooks configuration
    ${./setup-settings.sh}

    # Auto-launch claude
    exec claude
  '';
}
