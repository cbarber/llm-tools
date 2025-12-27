#!/usr/bin/env bash

# Setup OpenCode MCP and cclsp configuration based on detected project languages
# Only creates files if they don't already exist

set -euo pipefail

should_create_opencode=false
should_create_cclsp=false

[[ ! -f "opencode.json" ]] && should_create_opencode=true
[[ ! -f "cclsp.json" ]] && should_create_cclsp=true

if [[ "$should_create_opencode" == "false" && "$should_create_cclsp" == "false" ]]; then
  exit 0
fi

declare -A LANGUAGES=()
declare -A EXTENSIONS=()
declare -A COMMANDS=()

# Detect languages and map to LSP servers
if [[ -f "package.json" || -f "tsconfig.json" ]]; then
  LANGUAGES["typescript"]=1
  EXTENSIONS["typescript"]='["ts", "tsx", "js", "jsx"]'
  COMMANDS["typescript"]='["typescript-language-server", "--stdio"]'
fi

if [[ -f "Cargo.toml" ]]; then
  LANGUAGES["rust"]=1
  EXTENSIONS["rust"]='["rs"]'
  COMMANDS["rust"]='["rust-analyzer"]'
fi

if [[ -f "go.mod" ]]; then
  LANGUAGES["go"]=1
  EXTENSIONS["go"]='["go"]'
  COMMANDS["go"]='["gopls", "serve"]'
fi

if [[ -f "requirements.txt" || -f "pyproject.toml" || -f "setup.py" ]]; then
  LANGUAGES["python"]=1
  EXTENSIONS["python"]='["py"]'
  COMMANDS["python"]='["pyright-langserver", "--stdio"]'
fi

if [[ -f "flake.nix" || -f "default.nix" ]]; then
  LANGUAGES["nix"]=1
  EXTENSIONS["nix"]='["nix"]'
  COMMANDS["nix"]='["nil"]'
fi

if [[ -f "pom.xml" || -f "build.gradle" ]]; then
  LANGUAGES["java"]=1
  EXTENSIONS["java"]='["java"]'
  COMMANDS["java"]='["jdtls"]'
fi

if [[ -f "Gemfile" ]]; then
  LANGUAGES["ruby"]=1
  EXTENSIONS["ruby"]='["rb"]'
  COMMANDS["ruby"]='["solargraph", "stdio"]'
fi

if [[ -f "mix.exs" ]]; then
  LANGUAGES["elixir"]=1
  EXTENSIONS["elixir"]='["ex", "exs"]'
  COMMANDS["elixir"]='["elixir-ls"]'
fi

if [[ ${#LANGUAGES[@]} -eq 0 ]]; then
  exit 0
fi

# Create opencode.json with cclsp MCP server
if [[ "$should_create_opencode" == "true" ]]; then
  cat >opencode.json <<'EOF'
{
  "$schema": "https://opncd.ai/config.json",
  "share": "disabled",
  "mcp": {
    "lsp": {
      "type": "local",
      "command": ["cclsp"],
      "enabled": true,
      "environment": {
        "CCLSP_CONFIG_PATH": "cclsp.json"
      }
    }
  }
}
EOF
  echo "Created opencode.json with cclsp MCP server"
fi

# Create cclsp.json
if [[ "$should_create_cclsp" == "true" ]]; then
  cat >cclsp.json <<'EOF'
{
  "servers": [
EOF

  first=true
  for lang in "${!LANGUAGES[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo "," >>cclsp.json
    fi

    cat >>cclsp.json <<EOF
    {
      "extensions": ${EXTENSIONS[$lang]},
      "command": ${COMMANDS[$lang]},
      "rootDir": "."
    }
EOF
  done

  cat >>cclsp.json <<'EOF'
  ]
}
EOF
  echo "Created cclsp.json with language servers for: ${!LANGUAGES[*]}"
fi
