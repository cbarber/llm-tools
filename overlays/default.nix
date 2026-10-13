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
    version = "1.18.21";
    srcHash = "sha256-WKG/lts+wzDjYJ5pOZ0X4Kb0rJ1TzYQzQgjyQBY+bxs=";
    nodeModulesHash = "sha256-dGASaxZnxzJZY1PuDeqQCnYgMm2gEf5HZQsWOnt2JaU=";
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
        patches = (old.patches or [ ]) ++ [
          # /export and /copy read from the 100-message TUI store instead of
          # fetching full history; pre-compaction messages are silently dropped.
          ./patches/opencode-export-full-transcript.patch
        ];
        node_modules = old.node_modules.overrideAttrs (oldNm: {
          inherit version src;
          # 1.14.x expanded the workspace; override buildPhase to include all
          # required --filter targets. This supersedes the nixpkgs-inherited
          # buildPhase which only filtered ./packages/opencode --production.
          buildPhase = ''
            runHook preBuild
            export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
            bun install \
              --cpu="*" \
              --frozen-lockfile \
              --filter ./ \
              --filter ./packages/app \
              --filter ./packages/desktop \
              --filter ./packages/opencode \
              --filter ./packages/shared \
              --ignore-scripts \
              --no-progress \
              --os="*"
            bun --bun ./nix/scripts/canonicalize-node-modules.ts
            bun --bun ./nix/scripts/normalize-bun-binaries.ts
            runHook postBuild
          '';
          outputHash = opencode.nodeModulesHash;
        });
      })
    else
      prev.opencode;

  # claude-code is built from Anthropic's prebuilt binaries described by a
  # release manifest, which upstream exposes as an overridable argument. The
  # manifest pins the version and the per-platform checksums, so pointing it at
  # our vendored copy is the whole override — there is no version or hash to
  # track here. Refresh it with ./tools/update-package.sh claude-code [version].
  claude-code = prev.claude-code.override {
    manifest = prev.lib.importJSON ./manifest.zst.json;
  };
}
