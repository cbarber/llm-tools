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
    version = "1.2.26";
    srcHash = "sha256-+bQEfrqv9tAmXUMcvyUM0hJGpXgt09IWoKYt8I/jBlU=";
    nodeModulesHash = "sha256-byKXLpfvidfKl8PshUsW0grrRYRoVAYYlid0N6/ke2c=";
  };

  # ============================================================================
  # CLAUDE-CODE
  # ============================================================================
  claude-code = {
    version = "2.1.76";
    srcHash = "sha256-kjzPTG32f35eN6S85gGLUCmsNwH70Sq5rruEs/0hioM=";
    npmDepsHash = "";
  };

in
{
  # Apply opencode override if version is set
  opencode =
    if opencode.version != null then
      prev.opencode.overrideAttrs (old: rec {
        version = opencode.version;
        src = prev.fetchFromGitHub {
          owner = "anomalyco";
          repo = "opencode";
          tag = "v${version}";
          hash = opencode.srcHash;
        };
        patches = (old.patches or [ ]) ++ [ ];
        # Override node_modules FOD with new src and hash
        node_modules = old.node_modules.overrideAttrs (oldNm: {
          inherit version src;
          outputHash = opencode.nodeModulesHash;
        });
      })
    else
      prev.opencode;

  # Apply claude-code override if version is set
  claude-code =
    if claude-code.version != null then
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
