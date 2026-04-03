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
# This script:
#   1. Fetches the new src hash using nix-prefetch
#   2. Attempts to build to discover FOD hashes
#   3. Outputs the values to update in overlays/default.nix

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
  opencode      - Update opencode (fetches from GitHub)
  claude-code   - Update claude-code (fetches from npm)

If version is omitted, fetches the latest version.

Examples:
  $(basename "$0") opencode 1.1.12
  $(basename "$0") claude-code 2.1.3
  $(basename "$0") opencode  # Latest version
EOF
  exit 1
}

# Get latest opencode version from GitHub
get_latest_opencode_version() {
  curl -sL "https://api.github.com/repos/anomalyco/opencode/releases/latest" | \
    grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/'
}

# Get latest claude-code version from npm
get_latest_claude_code_version() {
  curl -sL "https://registry.npmjs.org/@anthropic-ai/claude-code/latest" | \
    grep -o '"version":"[^"]*"' | head -1 | sed 's/"version":"//;s/"//'
}

# Prefetch GitHub source and get hash
prefetch_github() {
  local owner="$1" repo="$2" version="$3"
  info "Prefetching $owner/$repo v$version from GitHub..."
  local nix32_hash
  nix32_hash=$(nix-prefetch-url --unpack "https://github.com/$owner/$repo/archive/refs/tags/v$version.tar.gz" 2>/dev/null)
  nix hash convert --hash-algo sha256 --from nix32 "$nix32_hash"
}

# Prefetch npm tarball and get hash
prefetch_npm() {
  local package="$1" version="$2"
  info "Prefetching $package@$version from npm..."
  local url
  url="https://registry.npmjs.org/$package/-/$(echo "$package" | sed 's/@.*\///')-$version.tgz"
  local nix32_hash
  nix32_hash=$(nix-prefetch-url --unpack "$url" 2>/dev/null)
  nix hash convert --hash-algo sha256 --from nix32 "$nix32_hash"
}

# Try to build and extract FOD hash from error
extract_fod_hash() {
  local attr="$1"
  info "Attempting build to discover FOD hash (this will fail, that's expected)..."

  # Build with empty hash to get the expected hash from error
  local output
  output=$(nix build ".#$attr" 2>&1 || true)

  # Extract hash from error message
  local hash
  hash=$(echo "$output" | grep -oE 'got:[[:space:]]*sha256-[A-Za-z0-9+/=]+' | sed 's/got:[[:space:]]*//' | head -1)

  if [[ -n "$hash" ]]; then
    echo "$hash"
  else
    echo ""
  fi
}

# Update overlay file with new values
update_overlay() {
  local package="$1" version="$2" src_hash="$3" fod_hash="$4"
  local escaped_src_hash="${src_hash//\//\\/}"
  local escaped_fod_hash="${fod_hash//\//\\/}"
  
  info "Updating $OVERLAY_FILE..."
  
  # Create backup
  cp "$OVERLAY_FILE" "$OVERLAY_FILE.bak"
  
  # Update the overlay using sed
  if [[ "$package" == "opencode" ]]; then
    sed -i "/opencode = {/,/};/ s/version = \"[^\"]*\";/version = \"$version\";/" "$OVERLAY_FILE"
    sed -i "/opencode = {/,/};/ s/srcHash = \"[^\"]*\";/srcHash = \"$escaped_src_hash\";/" "$OVERLAY_FILE"
    sed -i "/opencode = {/,/};/ s/nodeModulesHash = \"[^\"]*\";/nodeModulesHash = \"$escaped_fod_hash\";/" "$OVERLAY_FILE"
  elif [[ "$package" == "claude-code" ]]; then
    sed -i "/claude-code = {/,/};/ s/version = \"[^\"]*\";/version = \"$version\";/" "$OVERLAY_FILE"
    sed -i "/claude-code = {/,/};/ s/srcHash = \"[^\"]*\";/srcHash = \"$escaped_src_hash\";/" "$OVERLAY_FILE"
    sed -i "/claude-code = {/,/};/ s/npmDepsHash = \"[^\"]*\";/npmDepsHash = \"$escaped_fod_hash\";/" "$OVERLAY_FILE"
  fi
  
  success "Updated $OVERLAY_FILE"
  info "Backup saved to $OVERLAY_FILE.bak"
}

# Update opencode
update_opencode() {
  local version="${1:-}"

  if [[ -z "$version" ]]; then
    info "Fetching latest opencode version..."
    version=$(get_latest_opencode_version)
  fi

  info "Updating opencode to version $version"

  # Get src hash
  local src_hash
  src_hash=$(prefetch_github "anomalyco" "opencode" "$version")

  if [[ -z "$src_hash" ]]; then
    error "Failed to prefetch source"
    exit 1
  fi

  success "Source hash: $src_hash"

  # Temporarily update overlay with empty FOD hash
  info "Temporarily updating overlay with empty nodeModulesHash..."
  update_overlay "opencode" "$version" "$src_hash" ""

  # Attempt build to get the correct hash
  info "Building to discover nodeModulesHash (this will fail, that's expected)..."
  local node_modules_hash
  node_modules_hash=$(extract_fod_hash "packages.x86_64-linux.opencode")

  if [[ -z "$node_modules_hash" ]]; then
    error "Failed to extract nodeModulesHash from build output"
    error "Restoring backup..."
    mv "$OVERLAY_FILE.bak" "$OVERLAY_FILE"
    exit 1
  fi

  success "Node modules hash: $node_modules_hash"

  # Update overlay with the correct hash
  update_overlay "opencode" "$version" "$src_hash" "$node_modules_hash"
  
  # Remove backup
  rm -f "$OVERLAY_FILE.bak"

  echo ""
  success "Successfully updated opencode to version $version"
  echo ""
  echo "Changes made to $OVERLAY_FILE:"
  echo "  version: $version"
  echo "  srcHash: $src_hash"
  echo "  nodeModulesHash: $node_modules_hash"
  echo ""
  warn "Please verify the build works: nix build .#opencode"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Generate package-lock.json for claude-code by unpacking the npm tarball and
# running `npm install --package-lock-only` inside it.
# This mirrors the approach used by nixpkgs's nix-update --generate-lockfile:
# https://github.com/Mic92/nix-update/blob/main/nix_update/lockfile.py
generate_npm_lockfile() {
  local version="$1"
  local dest="$2"
  local tarball_url
  tarball_url="https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz"

  info "Generating package-lock.json via npm install --package-lock-only..."

  # Unpack tarball (npm tarballs use a package/ prefix)
  curl -sL "$tarball_url" | tar -xz -C "$tmpdir"
  local src_dir="${tmpdir}/package"

  # Remove any existing lock so npm resolves fresh
  rm -f "${src_dir}/package-lock.json"

  # Run npm in a nix shell that provides nodejs. Matches nixpkgs update.sh pattern:
  #   nix shell .#cacert .#nodejs ... --command bash
  AUTHORIZED=1 nix shell nixpkgs#nodejs --command \
    npm install --package-lock-only --prefix "$src_dir" 2>/dev/null

  if [[ ! -f "${src_dir}/package-lock.json" ]]; then
    error "npm failed to generate package-lock.json"
    return 1
  fi

  cp "${src_dir}/package-lock.json" "$dest"
  success "Generated package-lock.json at ${dest}"
}

# Update claude-code
update_claude_code() {
  local version="${1:-}"

  if [[ -z "$version" ]]; then
    info "Fetching latest claude-code version..."
    version=$(get_latest_claude_code_version)
  fi

  info "Updating claude-code to version $version"

  # Step 1: prefetch src hash
  local src_hash
  src_hash=$(prefetch_npm "@anthropic-ai/claude-code" "$version")

  if [[ -z "$src_hash" ]]; then
    error "Failed to prefetch source"
    exit 1
  fi
  success "Source hash: $src_hash"

  # Step 2: generate package-lock.json (needed for nixpkgs buildNpmPackage)
  local lock_file="${REPO_ROOT}/overlays/claude-code-package-lock.json"
  generate_npm_lockfile "$version" "$lock_file"

  # Step 3: write overlay with empty npmDepsHash so the build fails with the
  # correct hash in the error output (same trick used by nixpkgs update.sh)
  cp "$OVERLAY_FILE" "$OVERLAY_FILE.bak"
  update_overlay "claude-code" "$version" "$src_hash" ""

  # Step 4: build to discover npmDepsHash from Nix FOD error.
  # Build the npmDeps FOD directly with an empty outputHash so nix reports
  # the correct hash. We construct the expression inline with the new src and
  # postPatch so the result is independent of the overlay file's current state.
  info "Attempting build to discover npmDepsHash (this will fail, that's expected)..."
  local lock_file_nix_path
  lock_file_nix_path=$(nix-store --add "$lock_file")
  local nix_output npm_deps_hash
  nix_output=$(nix build --impure --no-link --expr \
    "let pkgs = import (builtins.getFlake \"nixpkgs\").outPath { system = builtins.currentSystem; config.allowUnfree = true; }; in
     (pkgs.claude-code.npmDeps.overrideAttrs (_: {
       src = pkgs.fetchzip {
         url = \"https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz\";
         hash = \"${src_hash}\";
       };
       postPatch = ''
         cp ${lock_file_nix_path} package-lock.json
         substituteInPlace cli.js --replace-fail '#!/bin/sh' '#!/usr/bin/env sh'
       '';
       outputHash = \"\";
       outputHashAlgo = \"sha256\";
     }))" \
    2>&1 || true)
  npm_deps_hash=$(echo "$nix_output" | grep -oE 'got:[[:space:]]*sha256-[A-Za-z0-9+/=]+' | sed 's/got:[[:space:]]*//' | tail -1)

  if [[ -z "$npm_deps_hash" ]]; then
    error "Failed to extract npmDepsHash from build output"
    mv "$OVERLAY_FILE.bak" "$OVERLAY_FILE"
    exit 1
  fi
  success "npmDepsHash: $npm_deps_hash"

  # Step 5: write final overlay with correct hash
  update_overlay "claude-code" "$version" "$src_hash" "$npm_deps_hash"
  rm -f "$OVERLAY_FILE.bak"

  echo ""
  success "Successfully updated claude-code to version $version"
  echo ""
  echo "Changes made:"
  echo "  ${OVERLAY_FILE}"
  echo "    version:     $version"
  echo "    srcHash:     $src_hash"
  echo "    npmDepsHash: $npm_deps_hash"
  echo "  ${lock_file}"
  echo ""
  warn "Verify the build: nix build .#claude-code"
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
