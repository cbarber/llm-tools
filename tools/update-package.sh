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
# For opencode this script:
#   1. Fetches the new src hash using nix-prefetch
#   2. Attempts to build to discover FOD hashes
#   3. Outputs the values to update in overlays/default.nix
#
# For claude-code it refreshes overlays/manifest.zst.json, which pins the
# version and the per-platform binary checksums on its own.

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
  claude-code   - Update claude-code (fetches the release manifest)

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

# Anthropic's release CDN, which serves both the version pointer and the
# per-version manifest that nixpkgs's claude-code derivation consumes.
CLAUDE_CODE_BASE_URL="https://downloads.claude.ai/claude-code-releases"

# Get latest claude-code version from the release CDN
get_latest_claude_code_version() {
  curl -fsSL "$CLAUDE_CODE_BASE_URL/latest"
}

# Prefetch GitHub source and get hash
prefetch_github() {
  local owner="$1" repo="$2" version="$3"
  info "Prefetching $owner/$repo v$version from GitHub..."
  local nix32_hash
  nix32_hash=$(nix-prefetch-url --unpack "https://github.com/$owner/$repo/archive/refs/tags/v$version.tar.gz" 2>/dev/null)
  nix hash convert --hash-algo sha256 --from nix32 "$nix32_hash"
}

# Build the opencode node_modules FOD directly with a sentinel hash and
# --option substitute false to force a local build. Nix will report the
# correct hash in its "hash mismatch" error regardless of lockfile issues.
compute_opencode_node_modules_hash() {
  local version="$1" src_hash="$2"
  info "Computing nodeModulesHash (building FOD with substitute disabled, this may take a while)..."

  # Sentinel value: valid SRI format but wrong — forces nix to build and report
  local sentinel="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

  local flake_src
  flake_src=$(nix eval --raw --impure --expr \
    "(builtins.fetchTree { type = \"git\"; url = \"file://${REPO_ROOT}\"; }).outPath" 2>/dev/null)

  local output
  output=$(nix build --impure --no-link --expr "
    let
      flake = builtins.getFlake \"path:${flake_src}\";
      pkgs = import (flake.inputs.nixpkgs) {
        system = builtins.currentSystem;
        config.allowUnfree = true;
        overlays = [ (import ${REPO_ROOT}/overlays) ];
      };
      src = pkgs.fetchFromGitHub {
        owner = \"anomalyco\";
        repo  = \"opencode\";
        tag   = \"v${version}\";
        hash  = \"${src_hash}\";
      };
    in
    pkgs.opencode.node_modules.overrideAttrs (_: {
      inherit src;
      version        = \"${version}\";
      outputHash     = \"${sentinel}\";
      outputHashAlgo = \"sha256\";
      outputHashMode = \"recursive\";
    })
  " 2>&1 || true)

  local hash
  hash=$(echo "$output" | grep -oE 'got:[[:space:]]*sha256-[A-Za-z0-9+/=]+' | sed 's/got:[[:space:]]*//' | tail -1)

  if [[ -n "$hash" ]]; then
    echo "$hash"
  else
    # Surface the raw output so the caller can diagnose
    echo "$output" >&2
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
  
  # Update the overlay using sed. claude-code is not handled here: it carries
  # no version or hash in the overlay, only overlays/manifest.zst.json.
  if [[ "$package" == "opencode" ]]; then
    sed -i "/opencode = {/,/};/ s/version = \"[^\"]*\";/version = \"$version\";/" "$OVERLAY_FILE"
    sed -i "/opencode = {/,/};/ s/srcHash = \"[^\"]*\";/srcHash = \"$escaped_src_hash\";/" "$OVERLAY_FILE"
    sed -i "/opencode = {/,/};/ s/nodeModulesHash = \"[^\"]*\";/nodeModulesHash = \"$escaped_fod_hash\";/" "$OVERLAY_FILE"
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

  # Compute the node_modules FOD hash by building with substitute disabled
  local node_modules_hash
  node_modules_hash=$(compute_opencode_node_modules_hash "$version" "$src_hash")

  if [[ -z "$node_modules_hash" ]]; then
    error "Failed to compute nodeModulesHash — see output above for details"
    exit 1
  fi

  success "Node modules hash: $node_modules_hash"

  # Update overlay with the correct hash
  update_overlay "opencode" "$version" "$src_hash" "$node_modules_hash"

  # Remove backup
  rm -f "$OVERLAY_FILE.bak"

  # Bump @opencode-ai/plugin and @opencode-ai/sdk in plugins package.json
  local plugins_pkg="$REPO_ROOT/agents/opencode/plugins/package.json"
  if [[ -f "$plugins_pkg" ]]; then
    info "Updating SDK versions in $plugins_pkg..."
    sed -i "s/\"@opencode-ai\/plugin\": \"[^\"]*\"/\"@opencode-ai\/plugin\": \"$version\"/" "$plugins_pkg"
    sed -i "s/\"@opencode-ai\/sdk\": \"[^\"]*\"/\"@opencode-ai\/sdk\": \"$version\"/" "$plugins_pkg"
    bun install --cwd "$REPO_ROOT/agents/opencode/plugins" 2>/dev/null
    success "Updated SDK versions to $version in $plugins_pkg"
  fi

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
