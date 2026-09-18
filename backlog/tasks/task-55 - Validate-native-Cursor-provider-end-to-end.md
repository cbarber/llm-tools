---
id: TASK-55
title: Validate native Cursor provider end to end
status: Done
assignee: []
created_date: '2026-09-24 04:44'
updated_date: '2026-09-25 14:45'
labels: []
dependencies: []
priority: high
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run nix flake check and a fresh nix develop .#opencode session outside the agent sandbox. Verify the pinned StableKernel provider loads, native read/shell/edit parts render, Temper queues each terminal provider-executed call once, one idle follow-up sees injected workflow context, restart/resume does not replay completed calls, and no credentials appear in logs. The implementation sandbox could not access the Nix daemon and live Cursor SDK traffic stalled before emitting events.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-24: Updated the pinned StableKernel provider to v0.9.0 at 577371b with freshly computed source and npm dependency hashes. Upstream typecheck, 616 tests, and build pass; Temper tests pass 5/5; setup-config Bats pass 2/2; local TypeScript check passes. Sandboxed nix flake check and nix build remain blocked by /nix/var/nix/daemon-socket permission. Live isolation reached provider doStream and Cursor Agent.send, but both OpenCode sidecar mode and a direct Node SDK run emitted no deltas and timed out; Bun Cursor.models.list also hangs while the same Node call returns 41 models. Keep task open pending an unsandboxed Nix build and real SDK turn.

2026-09-24: Diagnosed the sandbox live-turn stall as Cursor's HTTP/2 agent stream bypassing Fence proxy DNS. Node sidecar plus HTTP/1/SSE completed a real OpenCode turn. Live validation then produced structured provider-executed read, bash, and edit parts; Temper injected the edit workflow once at idle; restart/resume did not replay it; and instance disposal removed .cursor/rules/opencode.mdc. Added an opt-in sidecar HTTP/1 package patch and enabled it in the OpenCode shell. Automated Temper (5/5), setup-config Bats (2/2), TypeScript, and nixfmt checks pass. Keep open only because this sandbox still cannot access the Nix daemon to run nix build or nix flake check against the final derivation.

2026-09-24: Completion retry confirmed setup-config Bats 2/2, Temper tests 5/5, TypeScript, nixfmt, and git diff checks pass. The exact nix flake check/build remain blocked inside Fence by Nix daemon socket permissions, and the requested outside-sandbox diagnostic script has not been run (no sanitized final-launch or process-boundary logs exist). Keep this task open; do not claim completion until the exact Nix shell completes NATIVE_CURSOR_OK and the full native read/bash/edit acceptance loop.

2026-09-25: Final-artifact acceptance passed with the Nix-built OpenCode v1.18.21 and opencode-cursor 0.9.0 store artifacts under Fence. Native read, bash, and edit emitted completed structured parts with metadata.providerExecuted=true; Temper queued each persisted part ID once, injected mojo-commit at idle, and issued one follow-up. A fresh server process hydrated 9 historical messages, queued no completed calls, and returned RESUME_OK without tools. .cursor/rules/opencode.mdc existed during turns and was absent after normal one-shot disposal. Raw evidence contained neither credential patterns nor the injected CURSOR_API_KEY value. Gates: final nix flake check/build and NATIVE_CURSOR_OK launch passed in the unsandboxed diagnostic; setup-config Bats 2/2, Temper 5/5, TypeScript, nixfmt, upstream 616/616 tests, typecheck, and build passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Validated the native Cursor provider end to end against the final Nix artifact, including structured provider-executed tools, Temper idle injection, restart replay protection, generated-rule cleanup, and credential-safe logs.
<!-- SECTION:FINAL_SUMMARY:END -->
