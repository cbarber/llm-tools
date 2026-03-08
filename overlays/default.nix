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
    version = "1.2.15";
    srcHash = "sha256-26MV9TbyAF0KFqZtIHPYu6wqJwf0pNPdW/D3gDQEUlQ=";
    nodeModulesHash = "sha256-Diu/C8b5eKUn7MRTFBcN5qgJZTp0szg0ECkgEaQZ87Y=";
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
