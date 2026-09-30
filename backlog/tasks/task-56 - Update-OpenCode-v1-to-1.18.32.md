---
id: TASK-56
title: Update OpenCode v1 to 1.18.32
status: Done
assignee: []
created_date: '2026-09-25 14:47'
updated_date: '2026-09-25 19:51'
labels: []
dependencies: []
modified_files:
  - overlays/default.nix
  - agents/opencode/plugins/package.json
  - agents/opencode/plugins/bun.lock
priority: medium
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run tools/update-package.sh opencode 1.18.32 outside the agent sandbox to compute the real fetchFromGitHub and custom all-platform nodeModules hashes. Update @opencode-ai/plugin and @opencode-ai/sdk plus bun.lock, then rerun nix flake check, the OpenCode build, snapshots, Temper/setup-config gates, and the native Cursor no-tool/read/bash/edit/resume acceptance loop. Stay on OpenCode v1; do not adopt v2.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-25: Updated OpenCode v1 to 1.18.32 using repository-specific source and all-platform nodeModules hashes, and aligned @opencode-ai/plugin, @opencode-ai/sdk, and bun.lock. Gates passed: nix build for OpenCode/provider, nix flake check, setup-config Bats 2/2, Temper 5/5, TypeScript, nixfmt, git diff checks, and the v1.18.32 event-recorder suite 13/13 with 5 snapshots. Live Nix-shell acceptance passed for NATIVE_CURSOR_OK, provider-executed read/bash/edit, ACCEPTANCE_OK, same-session RESUME_OK with no replayed tools, generated-rule cleanup, and credential-safe logs.

2026-09-25: Reopened after review because the OpenCode 1.18.32 one-shot acceptance proved provider-executed tools reached Temper's queue but did not explicitly capture the idle workflow injection and follow-up. Complete a persistent-server final-artifact run before considering the update fully validated.

2026-09-25: Final persistent-server acceptance passed against the Nix-built OpenCode 1.18.32 artifact. Four requested native read/bash/read/edit parts were persisted with providerExecuted=true; Temper queued each once, injected mojo-commit exactly once at session.idle, and issued exactly one resume-multi follow-up. After a fresh server process resumed the same session, Temper hydrated history once, queued no completed calls, and returned RESUME_OK without tools. Normal one-shot disposal removed .cursor/rules/opencode.mdc, and raw server/client/cleanup logs contained neither credential patterns nor the injected CURSOR_API_KEY value.

2026-09-25: Persistent final-artifact acceptance completed against OpenCode 1.18.32. Session ses_f25e38869ffeYbresOAtiNpRcA emitted completed provider-executed read, bash, preparatory read, and edit parts; Temper injected mojo-commit once at session.idle and produced exactly one resume-multi:2 follow-up. A fresh server hydrated 8 historical messages, queued no completed provider tools, and returned RESUME_OK without tools. Normal one-shot disposal removed .cursor/rules/opencode.mdc, and raw persistent logs passed credential scans. Revalidated nix flake check, OpenCode/provider builds, setup-config Bats 2/2, Temper 5/5, TypeScript, nixfmt, git diff checks, and the v1.18.32 event-recorder suite 13/13 with 5 snapshots.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Updated OpenCode to 1.18.32 and validated the final Nix artifact end to end, including native Cursor tools, Temper idle follow-up, restart replay protection, generated-rule cleanup, and credential-safe logs.
<!-- SECTION:FINAL_SUMMARY:END -->
