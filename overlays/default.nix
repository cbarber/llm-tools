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
    version = "1.14.22";
    srcHash = "sha256-T/Dk9Izh/DbbpY5fENJN4xFPMOUfKYNHGkuoY4HBpP0=";
    nodeModulesHash = "sha256-wQmsgZQGoedvn2RHINfKh9cVwSNYgkGaBOdV/AD70jQ=";
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
