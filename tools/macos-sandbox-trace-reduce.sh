#!/usr/bin/env bash
# Reduce fs_usage_paths.txt to a minimal set of (subpath ...) seatbelt rules.
#
# Usage: macos-sandbox-trace-reduce.sh < fs_usage_paths.txt
#
# Reads one absolute path per line, outputs seatbelt (allow file-read* ...) stanzas
# with paths collapsed to their lowest common ancestor where safe to do so.
#
# "Safe to collapse" means the parent is not a sensitivity boundary. Boundaries
# prevent collapsing ~/.ssh into ~/ just because both id_rsa and agent-key were
# accessed — the agent should only ever see agent-* keys.

set -euo pipefail

# Paths we refuse to collapse above, even if many siblings are accessed.
# Ordered from most-specific to least-specific for prefix matching.
BOUNDARIES=(
    "$HOME/.ssh"
    "$HOME/.aws"
    "$HOME/.config/gh"
    "$HOME/.gnupg"
    "$HOME/Documents"
    "$HOME/Downloads"
    "$HOME/Desktop"
    "$HOME"
)

is_boundary() {
    local path="$1"
    for boundary in "${BOUNDARIES[@]}"; do
        [[ "$path" == "$boundary" ]] && return 0
    done
    return 1
}

# Returns the parent of a path, or the path itself if it has no parent.
parent_of() {
    local path="${1%/*}"
    [[ -z "$path" ]] && echo "/" || echo "$path"
}

# Collapse a sorted list of paths to their minimal covering set.
# A set of siblings is collapsed to their parent when ALL of:
#   1. Parent is not a sensitivity boundary
#   2. At least LCD_THRESHOLD siblings are accessed from the same parent
#      (avoids collapsing /usr/bin just because two binaries were accessed)
LCD_THRESHOLD=5

reduce_paths() {
    local -a paths=("$@")
    local -A parent_counts=()
    local -A parent_blocked=()

    for path in "${paths[@]}"; do
        local parent
        parent=$(parent_of "$path")
        parent_counts["$parent"]=$(( ${parent_counts["$parent"]:-0} + 1 ))
        if is_boundary "$parent"; then
            parent_blocked["$parent"]=1
        fi
    done

    local -a result=()
    local -A emitted=()

    for path in "${paths[@]}"; do
        local parent
        parent=$(parent_of "$path")
        local count="${parent_counts["$parent"]:-0}"
        local blocked="${parent_blocked["$parent"]:-0}"

        if [[ "$count" -ge "$LCD_THRESHOLD" ]] && [[ "$blocked" != "1" ]]; then
            local emit="$parent"
        else
            local emit="$path"
        fi

        if [[ -z "${emitted["$emit"]:-}" ]]; then
            result+=("$emit")
            emitted["$emit"]=1
        fi
    done

    printf '%s\n' "${result[@]}"
}

# Read paths from stdin, deduplicate, then reduce.
mapfile -t raw_paths < <(sort -u)

[[ ${#raw_paths[@]} -eq 0 ]] && { echo "No paths on stdin" >&2; exit 1; }

mapfile -t reduced < <(reduce_paths "${raw_paths[@]}")

echo "(allow file-read*"
for path in "${reduced[@]}"; do
    printf '  (subpath "%s")\n' "$path"
done
echo ")"
