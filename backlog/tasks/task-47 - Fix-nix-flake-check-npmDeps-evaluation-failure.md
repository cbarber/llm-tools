---
id: TASK-47
title: Fix nix flake check npmDeps evaluation failure
status: To Do
assignee: []
created_date: '2026-09-24 02:38'
updated_date: '2026-09-25 21:34'
labels: []
dependencies: []
priority: high
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
nix flake check fails while evaluating packages.x86_64-linux.claude-code because overlays/default.nix assumes old.npmDeps exists at line 95. Reproduce with: nix flake check. Update the overlay for the current upstream Claude Code derivation, then rerun the full flake check.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-25: Reproduced during mojo-complete after ACP mid-turn-input research. nix flake check still fails evaluating packages.x86_64-linux.claude-code at overlays/default.nix:95 because old.npmDeps is missing; targeted nix build .#temper-acp succeeds.
<!-- SECTION:NOTES:END -->
