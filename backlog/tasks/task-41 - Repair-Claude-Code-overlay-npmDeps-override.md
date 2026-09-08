---
id: TASK-41
title: Repair Claude Code overlay npmDeps override
status: To Do
assignee: []
created_date: '2026-08-22 21:52'
updated_date: '2026-09-08 02:01'
labels: []
dependencies: []
priority: high
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
nix flake check fails while evaluating packages.x86_64-linux.claude-code because overlays/default.nix expects old.npmDeps, which is absent in the current nixpkgs package. Update the overlay for the current package shape and restore flake validation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 nix flake check completes successfully
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-07: Reproduced during feat/cursor-cli-runtime completion. nix flake check fails at overlays/default.nix:95 because old.npmDeps is absent. The targeted cursor-cli derivation still builds successfully.
<!-- SECTION:NOTES:END -->
