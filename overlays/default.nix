# Package overrides, applied on top of whatever the pinned nixpkgs provides.
#
# Refresh claude-code with: ./tools/update-package.sh claude-code [version]
#
final: prev: {
  # opencode carries a local fix only. nixpkgs is at or ahead of the version we
  # used to pin, and its node_modules build already filters every workspace
  # package, so overriding the version, hashes, or the build phase would now
  # hold opencode back rather than move it forward. The node_modules derivation
  # inherits only version and src, so patches do not disturb its output hash.
  opencode = prev.opencode.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      # /export and /copy read from the 100-message TUI store instead of
      # fetching full history; pre-compaction messages are silently dropped.
      ./patches/opencode-export-full-transcript.patch
    ];
  });

  # claude-code is built from Anthropic's prebuilt binaries described by a
  # release manifest, which upstream exposes as an overridable argument. The
  # manifest pins the version and the per-platform checksums, so pointing it at
  # our vendored copy is the whole override — there is no version or hash to
  # track here. Refresh it with ./tools/update-package.sh claude-code [version].
  claude-code = prev.claude-code.override {
    manifest = prev.lib.importJSON ./manifest.zst.json;
  };
}
