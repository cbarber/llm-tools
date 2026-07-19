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
    version = "1.17.11";
    srcHash = "sha256-ZgmRHoI3rxsSM10sA4cZu/FxqwmgawQvlW3eykXQsqQ=";
    nodeModulesHash = "sha256-PhFDNxeJHTQdT8mAJz7hVKnsUL3Ez6NSgnUSMz3LUqY=";
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
          # TUI command was missing --dangerously-skip-permissions; only run had it.
          ./patches/opencode-tui-dangerously-skip-permissions.patch
        ];
        node_modules = old.node_modules.overrideAttrs (oldNm: {
          inherit version src;
          # ghostty-web is a git-sourced dependency whose pinned commit in the
          # bun.lock diverges from what bun resolves at v1.17.11 tag time.
          # Update the lockfile before bun install --frozen-lockfile runs.
          postPatch = (oldNm.postPatch or "") + ''
            substituteInPlace bun.lock \
              --replace-fail \
              '"ghostty-web": ["ghostty-web@github:anomalyco/ghostty-web#20bd361", {}, "anomalyco-ghostty-web-20bd361", "sha512-dW0nwaiBBcun9y5WJSvm3HxDLe5o9V0xLCndQvWonRVubU8CS1PHxZpLffyPt1YujPWC13ez03aWxcuKBPYYGQ=="]' \
              '"ghostty-web": ["ghostty-web@github:anomalyco/ghostty-web#513463a", {}, "anomalyco-ghostty-web-513463a", "sha512-GZR8LSmgGzViWnBJrqRI8MpAZRCJxhcr1Hi9Tyeh7YRooHZQjK9J97FQRD3tbBaM2wjq05gzGY2UEsG+JtZeBw=="]'
          '';
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
