#!/usr/bin/env bash

# Setup MCP configuration for Claude Code based on detected project languages
# Only creates .mcp.json if it doesn't already exist

set -euo pipefail

if [[ -f ".mcp.json" ]]; then
  exit 0
fi

declare -A LANGUAGES=()

[[ -f "package.json" ]] && LANGUAGES["typescript"]="typescript-language-server -- --stdio"
[[ -f "tsconfig.json" ]] && LANGUAGES["typescript"]="typescript-language-server -- --stdio"
[[ -f "Cargo.toml" ]] && LANGUAGES["rust"]="rust-analyzer"
[[ -f "go.mod" ]] && LANGUAGES["go"]="gopls"
[[ -f "requirements.txt" || -f "pyproject.toml" || -f "setup.py" ]] && LANGUAGES["python"]="pyright-langserver -- --stdio"
[[ -f "flake.nix" || -f "default.nix" ]] && LANGUAGES["nix"]="nil"
[[ -f "pom.xml" || -f "build.gradle" ]] && LANGUAGES["java"]="jdtls"
[[ -f "Gemfile" ]] && LANGUAGES["ruby"]="solargraph stdio"
[[ -f "mix.exs" ]] && LANGUAGES["elixir"]="elixir-ls"
[[ -f "pubspec.yaml" ]] && LANGUAGES["dart"]="dart_language_server"

if [[ ${#LANGUAGES[@]} -eq 0 ]]; then
  exit 0
fi

cat >.mcp.json <<'EOF'
{
  "mcpServers": {
EOF

first=true
for lang in "${!LANGUAGES[@]}"; do
  if [[ "$first" == "true" ]]; then
    first=false
  else
    echo "," >>.mcp.json
  fi

  lsp_cmd="${LANGUAGES[$lang]}"
  if [[ "$lsp_cmd" == *" -- "* ]]; then
    lsp_name="${lsp_cmd%% -- *}"
    lsp_args="${lsp_cmd#* -- }"
    args_json="[\"--workspace\", \".\", \"--lsp\", \"$lsp_name\", \"--\", \"$lsp_args\"]"
  else
    args_json="[\"--workspace\", \".\", \"--lsp\", \"$lsp_cmd\"]"
  fi

  cat >>.mcp.json <<EOF
    "$lang-language-server": {
      "command": "mcp-language-server",
      "args": $args_json
    }
EOF
done

cat >>.mcp.json <<'EOF'
  }
}
EOF

echo "Created .mcp.json with language servers for: ${!LANGUAGES[*]}"

