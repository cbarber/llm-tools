# Package version overrides for faster updates
#
# Update these values using: ./tools/update-package.sh <package-name> [version]
#
# Example:
#   ./tools/update-package.sh opencode 1.1.12
#   ./tools/update-package.sh claude-code 2.1.3
#
final: prev:
let
  # ============================================================================
  # OPENCODE
  # ============================================================================
  opencode = {
    version = "1.1.12";
    srcHash = "sha256-k6wRBtWFwyLWJ6R0el3dY/nBlg2t+XkTpsuEseLXp+E=";
    nodeModulesHash = "sha256-vRIWQt02VljcoYG3mwJy8uCihSTB/OLypyw+vt8LuL8=";
  };

  # ============================================================================
  # CLAUDE-CODE
  # ============================================================================
  claude-code = {
    version = "2.1.3";
    srcHash = "sha256-IF0ZQ2ddjtoQ6J9lXaqrak9Wi6pCCIqnMu2l8woHZIs=";
    npmDepsHash = "sha256-hE9nlLr3KUuhu5DMNsHFao97CR9GnbJajz2GN+IEeqA=";
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
      node_modules = old.node_modules.overrideAttrs (oldNm: {
        inherit version src;
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
