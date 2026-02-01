#!/usr/bin/env bash
# check-shell-scripts - Run shellcheck on modified shell scripts
#
# Usage:
#   check-shell-scripts           # Check staged files (pre-commit)
#   check-shell-scripts --all     # Check all shell scripts
#   check-shell-scripts file.sh   # Check specific file

set -euo pipefail

MODE="${1:---staged}"

check_file() {
  local file="$1"
  
  if ! shellcheck --severity=error "$file"; then
    echo "❌ Shellcheck failed: $file" >&2
    return 1
  fi
  
  return 0
}

case "$MODE" in
  --all)
    echo "Checking all shell scripts..."
    failed=0
    while IFS= read -r -d '' file; do
      check_file "$file" || ((failed++))
    done < <(find . -type f \( -name "*.sh" -o \( -path "*/tools/*" -executable \) \) \
      -not -path "./.git/*" \
      -not -path "./repo-backup/*" \
      -not -name "*.md" \
      -print0)
    
    if [[ $failed -gt 0 ]]; then
      echo "❌ $failed file(s) failed shellcheck" >&2
      exit 1
    fi
    echo "✓ All shell scripts passed shellcheck"
    ;;
    
  --staged)
    echo "Checking staged shell scripts..."
    failed=0
    
    # Get staged files
    while IFS= read -r file; do
      # Check if it's a shell script
      if [[ "$file" == *.sh ]] || [[ "$file" == tools/* ]]; then
        if [[ -f "$file" ]]; then
          check_file "$file" || ((failed++))
        fi
      fi
    done < <(git diff --cached --name-only --diff-filter=ACM)
    
    if [[ $failed -gt 0 ]]; then
      echo "❌ $failed staged file(s) failed shellcheck" >&2
      echo "Fix the issues or use 'git commit --no-verify' to skip this check" >&2
      exit 1
    fi
    
    if [[ $failed -eq 0 ]]; then
      echo "✓ All staged shell scripts passed shellcheck"
    fi
    ;;
    
  *)
    # Check specific file
    check_file "$MODE"
    echo "✓ $MODE passed shellcheck"
    ;;
esac
