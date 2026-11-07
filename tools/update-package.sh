#!/usr/bin/env bash
# Update package version overrides
#
# Usage: ./tools/update-package.sh <package> [version]
#
# Examples:
#   ./tools/update-package.sh opencode 1.1.12
#   ./tools/update-package.sh claude-code 2.1.3
#   ./tools/update-package.sh opencode          # Uses latest from GitHub/npm
#
# For claude-code this refreshes overlays/manifest.zst.json, which pins the
# version and the per-platform binary checksums on its own.
#
# For opencode it aligns the plugin SDKs with the packaged opencode. opencode
# itself is not pinned in the overlay, so moving it means `nix flake update`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OVERLAY_FILE="$REPO_ROOT/overlays/default.nix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}==>${NC} $*" >&2; }
success() { echo -e "${GREEN}==>${NC} $*" >&2; }
warn() { echo -e "${YELLOW}==>${NC} $*" >&2; }
error() { echo -e "${RED}==>${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <package> [version]

Packages:
  opencode      - Align the plugin SDKs with the packaged opencode
  claude-code   - Update claude-code (fetches the release manifest)

If version is omitted, claude-code takes the latest release and opencode
takes whatever the pinned nixpkgs provides.

Examples:
  $(basename "$0") claude-code 2.1.3
  $(basename "$0") claude-code  # Latest release
  $(basename "$0") opencode     # Match the packaged opencode
EOF
  exit 1
}

# Get latest opencode version from GitHub
get_latest_opencode_version() {
  curl -sL "https://api.github.com/repos/anomalyco/opencode/releases/latest" | \
    grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/'
}

# Anthropic's release CDN, which serves both the version pointer and the
# per-version manifest that nixpkgs's claude-code derivation consumes.
CLAUDE_CODE_BASE_URL="https://downloads.claude.ai/claude-code-releases"

# Get latest claude-code version from the release CDN
get_latest_claude_code_version() {
  curl -fsSL "$CLAUDE_CODE_BASE_URL/latest"
}

# Update opencode
#
# The overlay no longer pins opencode: it tracks whatever the pinned nixpkgs
# provides and carries only a local patch, so moving opencode itself means
# `nix flake update`. What this aligns is the plugin SDK pair, which has to
# match the opencode the shell actually runs — a mismatch there breaks the
# temper plugin against the running server.
update_opencode() {
  local system packaged latest version
  system=$(nix eval --raw --impure --expr builtins.currentSystem)
  packaged=$(nix eval --raw "${REPO_ROOT}#devShells.${system}.pkgs.opencode.version" 2>/dev/null || true)

  if [[ -z "$packaged" ]]; then
    error "Could not read the packaged opencode version from the flake"
    exit 1
  fi

  version="${1:-$packaged}"
  info "nixpkgs provides opencode $packaged"

  if [[ "$version" != "$packaged" ]]; then
    warn "Requested $version but the shell runs $packaged; the SDKs will not match the server."
  fi

  latest=$(get_latest_opencode_version 2>/dev/null || true)
  if [[ -n "$latest" && "$latest" != "$packaged" ]]; then
    warn "Upstream latest is $latest. Run 'nix flake update' to move nixpkgs, or"
    warn "add a version override to $OVERLAY_FILE to get ahead of it."
  fi

  local plugins_pkg="$REPO_ROOT/agents/opencode/plugins/package.json"
  if [[ ! -f "$plugins_pkg" ]]; then
    error "Missing $plugins_pkg"
    exit 1
  fi

  info "Aligning plugin SDKs with opencode $version..."
  sed -i "s/\"@opencode-ai\/plugin\": \"[^\"]*\"/\"@opencode-ai\/plugin\": \"$version\"/" "$plugins_pkg"
  sed -i "s/\"@opencode-ai\/sdk\": \"[^\"]*\"/\"@opencode-ai\/sdk\": \"$version\"/" "$plugins_pkg"
  bun install --cwd "$REPO_ROOT/agents/opencode/plugins"

  echo ""
  success "Plugin SDKs aligned with opencode $version"
  echo ""
  echo "Changes made:"
  echo "  ${plugins_pkg}"
  echo "  $(dirname "$plugins_pkg")/bun.lock"
  echo ""
  warn "Verify the build: nix build .#devShells.${system}.pkgs.opencode"
}

# Update claude-code
#
# Upstream nixpkgs no longer builds claude-code from the npm tarball; it
# installs Anthropic's prebuilt binaries described by a per-release manifest.
# That manifest carries the version and the per-platform checksums, so there is
# no source to prefetch and no FOD hash to discover — updating claude-code is
# just refreshing overlays/manifest.zst.json.
update_claude_code() {
  local version="${1:-}"

  if [[ -z "$version" ]]; then
    info "Fetching latest claude-code version..."
    version=$(get_latest_claude_code_version)
  fi

  if [[ -z "$version" ]]; then
    error "Failed to determine the latest claude-code version"
    exit 1
  fi

  info "Updating claude-code to version $version"

  local manifest_file="${REPO_ROOT}/overlays/manifest.zst.json"
  local manifest_url="${CLAUDE_CODE_BASE_URL}/${version}/manifest.zst.json"

  info "Fetching $manifest_url"
  if ! curl -fsSL "$manifest_url" --output "${manifest_file}.tmp"; then
    error "Failed to fetch the manifest for version $version"
    rm -f "${manifest_file}.tmp"
    exit 1
  fi

  # Guard against a CDN error page or a manifest for an unexpected version.
  local manifest_version
  manifest_version=$(nix eval --raw --impure --expr \
    "(builtins.fromJSON (builtins.readFile \"${manifest_file}.tmp\")).version" 2>/dev/null || true)

  if [[ "$manifest_version" != "$version" ]]; then
    error "Manifest version mismatch: asked for $version, got '${manifest_version:-unparseable JSON}'"
    rm -f "${manifest_file}.tmp"
    exit 1
  fi

  mv "${manifest_file}.tmp" "$manifest_file"
  success "Wrote $manifest_file"

  # The flake only sees git-tracked files, so a new manifest has to be staged
  # before nix can read it.
  git -C "$REPO_ROOT" add "$manifest_file"

  echo ""
  success "Successfully updated claude-code to version $version"
  echo ""
  echo "Changes made:"
  echo "  ${manifest_file}"
  echo "    version: $manifest_version"
  echo ""
  warn "Verify the build: nix build .#devShells.\$(nix eval --raw --impure --expr builtins.currentSystem).pkgs.claude-code"
}

# Main
main() {
  if [[ $# -lt 1 ]]; then
    usage
  fi

  local package="$1"
  local version="${2:-}"

  case "$package" in
    opencode)
      update_opencode "$version"
      ;;
    claude-code)
      update_claude_code "$version"
      ;;
    *)
      error "Unknown package: $package"
      usage
      ;;
  esac
}

main "$@"
