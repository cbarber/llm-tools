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
    version = "1.3.3";
    srcHash = "sha256-hHyG1s/aaIDpZOF/ZGd0BgBK/DLHfsLZjbbYcYhbFeQ=";
    nodeModulesHash = "sha256-v9VF9n+fCydp373whhgopj8M+gzRGivy8iBErnqK4dw=";
  };

  # ============================================================================
  # CLAUDE-CODE
  # ============================================================================
  claude-code = {
    version = "2.1.91";
    srcHash = "sha256-u7jdM6hTYN05ZLPz630Yj7gI0PeCSArg4O6ItQRAMy4=";
    npmDepsHash = "sha256-0ppKP+XMgTzVVZtL7GDsOjgvSPUDrUa7SoG048RLaNg=";
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
        # 1.3.3+ calls `bun run vite build` which spawns vite.js via #!/usr/bin/env node.
        # The node_modules FOD is copied read-only from the store, so we chmod before
        # patching the shebang — same pattern as nixpkgs/tinyauth.
        postConfigure = (old.postConfigure or "") + ''
          chmod +w packages/app/node_modules/vite/bin/vite.js
          substituteInPlace packages/app/node_modules/vite/bin/vite.js \
            --replace-fail "/usr/bin/env node" "${prev.lib.getExe prev.bun}"
        '';
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
        # nixpkgs vendors a package-lock.json pinned to its own version.
        # Override postPatch to substitute our version-matched lock file.
        postPatch = ''
          cp ${./claude-code-package-lock.json} package-lock.json
          substituteInPlace cli.js \
            --replace-fail '#!/bin/sh' '#!/usr/bin/env sh'
        '';
        # buildNpmPackage bakes npmDeps (a fetchNpmDeps FOD) at evaluation time
        # using the original finalAttrs src. overrideAttrs does not re-evaluate
        # it, so we must explicitly re-derive it from our new src + postPatch.
        npmDeps = old.npmDeps.overrideAttrs {
          inherit src postPatch;
          outputHash = claude-code.npmDepsHash;
        };
      })
    else
      prev.claude-code;
}
