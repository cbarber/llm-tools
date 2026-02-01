#!/usr/bin/env bash

# Common helper functions for Claude Code scripts
# Source this file in other scripts for shared functionality

# Detect project languages based on indicator files
detect_languages() {
    local -A languages=()
    
    [[ -f "package.json" || -f "tsconfig.json" ]] && languages["javascript"]=1
    [[ -f "Cargo.toml" ]] && languages["rust"]=1
    [[ -f "go.mod" ]] && languages["go"]=1
    [[ -f "pyproject.toml" || -f "requirements.txt" || -f "setup.py" ]] && languages["python"]=1
    [[ -f "flake.nix" || -f "default.nix" ]] && languages["nix"]=1
    [[ -f "pom.xml" || -f "build.gradle" ]] && languages["java"]=1
    [[ -f "Gemfile" ]] && languages["ruby"]=1
    [[ -f "mix.exs" ]] && languages["elixir"]=1
    [[ -f "pubspec.yaml" ]] && languages["dart"]=1
    
    echo "${!languages[@]}"
}

# Check if a Makefile target exists
has_make_target() {
    local target="$1"
    [[ -f "Makefile" ]] && grep -q "^${target}:" Makefile
}

# Run a command with error handling and output capture
run_with_feedback() {
    local description="$1"
    local command="$2"
    
    echo "→ $description"
    if eval "$command"; then
        echo "✓ $description passed"
        return 0
    else
        echo "✗ $description failed"
        return 1
    fi
}

# Parse JSON input from Claude Code hooks
parse_claude_input() {
    if [[ -t 0 ]]; then
        echo "Error: No JSON input from Claude Code" >&2
        return 1
    fi
    
    local input
    input=$(cat)
    
    # Extract common fields
    CLAUDE_EVENT_TYPE=$(echo "$input" | jq -r '.eventType // "unknown"')
    CLAUDE_TOOL_NAME=$(echo "$input" | jq -r '.params.name // "unknown"')
    CLAUDE_FILE_PATH=$(echo "$input" | jq -r '.params.file_path // ""')
    
    export CLAUDE_EVENT_TYPE CLAUDE_TOOL_NAME CLAUDE_FILE_PATH
    echo "$input"
}

# Check if we should skip processing based on file patterns
should_skip_file() {
    local file_path="$1"
    
    # Skip common non-source files
    case "$file_path" in
        *.log|*.tmp|*.temp|*~|*.bak) return 0 ;;
        .git/*|node_modules/*|target/*|build/*|dist/*) return 0 ;;
        *.md|*.txt|*.json|*.yaml|*.yml) return 0 ;;
    esac
    
    # Check .claude-hooks-ignore file if it exists
    if [[ -f ".claude-hooks-ignore" ]]; then
        while IFS= read -r pattern; do
            [[ -n "$pattern" && "$file_path" == "$pattern" ]] && return 0
        done < .claude-hooks-ignore
    fi
    
    return 1
}

# Log debug messages if debug mode is enabled
log_debug() {
    if [[ "${CLAUDE_HOOKS_DEBUG:-0}" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}