---
id: TASK-57
title: Validate Cursor CLI ACP startup under Fence
status: Done
assignee: []
created_date: '2026-09-26 22:58'
updated_date: '2026-09-27 23:28'
labels: []
dependencies: []
priority: high
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run nix develop .#cursor-cli with valid Cursor and GitHub credentials outside the existing agent sandbox. Confirm Toad completes ACP initialize and session/new through the Symposium and Temper chain after Cursor traffic is routed through Fence's authenticated proxy. Capture sanitized diagnostics for any remaining session-service failure and verify no credentials appear in logs.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-27: Added agents/cursor-cli/test-acp-startup.sh. From the cursor-cli Nix shell it enters the same agent-sandbox, starts the configured conductor/Temper/Cursor ACP chain, sends initialize and session/new, and passes only when session/new returns a session ID. The OpenCode-sandbox control run deterministically reaches session/new and reports Failed to initialize session services; run the probe from the authenticated cursor-cli shell for the real acceptance result.

2026-09-27: Authenticated acceptance passed inside agent-sandbox after selecting AGENT_CLI_CREDENTIAL_STORE=memory. The probe traversed conductor and Temper, discovered the full Cursor model catalog, and session/new returned a session ID. The cursor-cli shell now sets memory storage by default so Cursor uses the iron-proxy-injected API key instead of an unavailable macOS Keychain/file credential.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Validated Cursor CLI ACP startup under Fence. The sandbox now uses memory-only credential storage with iron-proxy API-key injection; the deterministic startup probe confirms initialize and session/new complete successfully.
<!-- SECTION:FINAL_SUMMARY:END -->
