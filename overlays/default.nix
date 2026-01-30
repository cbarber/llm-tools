# Package version overrides for faster updates
#
# Update these values using: ./tools/update-package.sh <package-name> [version]
#
# Example:
#   ./tools/update-package.sh opencode <version>
#   ./tools/update-package.sh claude-code <version>
#
final: prev:
let
  # ============================================================================
  # OPENCODE
  # ============================================================================
  opencode = {
    version = "1.1.43";
    srcHash = "sha256-+CBqfdK3mw5qnl4sViFEcTSslW0sOE53AtryD2MdhTI=";
    # Hash calculated with pinned bun 1.3.6
    nodeModulesHash = "sha256-zkinMkPR1hCBbB5BIuqozQZDpjX4eiFXjM6lpwUx1fM=";
  };

  # ============================================================================
  # CLAUDE-CODE
  # ============================================================================
  claude-code = {
    version = "2.1.12";
    srcHash = "sha256-JX72YEM2fXY7qKVkuk+UFeef0OhBffljpFBjIECHMXw=";
    npmDepsHash = "";
  };

in
{
  # Apply opencode override if version is set
  opencode = if opencode.version != null then
    prev.opencode.overrideAttrs (old: rec {
      version = opencode.version;
      src = prev.fetchFromGitHub {
        owner = "anomalyco";
        repo = "opencode";
        tag = "v${version}";
        hash = opencode.srcHash;
      };
      # Override node_modules FOD with new src and hash
      # Pin bun version to ensure reproducible builds across nixpkgs updates
      node_modules = old.node_modules.overrideAttrs (oldNm: {
        inherit version src;
        nativeBuildInputs = [
          (prev.bun.overrideAttrs (oldBun: {
            version = "1.3.6";
            src = prev.fetchurl {
              url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.6/bun-linux-x64.zip";
              hash = "sha256-bq+bs/BdzNsGa2e1xzVp3LglSbRStM/nW9QLcQVKEP0=";
            };
          }))
          oldNm.nativeBuildInputs
        ];
        outputHash = opencode.nodeModulesHash;
      });
    })
  else
    prev.opencode;

  # Apply claude-code override if version is set
  claude-code = if claude-code.version != null then
    prev.claude-code.overrideAttrs (old: rec {
      version = claude-code.version;
      src = prev.fetchzip {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = claude-code.srcHash;
      };
      npmDepsHash = claude-code.npmDepsHash;
      # package-lock.json is handled by the update script
    })
  else
    prev.claude-code;
}
