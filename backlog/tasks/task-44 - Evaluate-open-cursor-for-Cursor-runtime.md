---
id: TASK-44
title: Evaluate open-cursor for Cursor runtime
status: Done
assignee: []
created_date: '2026-09-18 02:46'
updated_date: '2026-09-19 02:36'
labels: []
dependencies: []
priority: medium
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Assess Nomadcxx/open-cursor as an OpenCode-native replacement for the Toad and ACP frontend path. Verify compatibility with the Temper OpenCode plugin, Cursor authentication, Fence sandboxing, streaming, tool calls, usage reporting, and Nix packaging before deciding whether to replace the current runtime.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Final implementation packages open-cursor 2.5.8 as a pinned patched Nix derivation. OpenCode-owned mode suppresses global V1/V2 tool registration, rejects unknown cursor-agent tool passthrough, and disables the duplicate MCP bridge so Temper remains authoritative. Pre-start cursor-agent model discovery populates the model picker from OAuth with a five-second timeout and preserves the previous catalog when offline.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Integrated a reproducible patched open-cursor provider into the standard OpenCode environment. Cursor models are discovered from the authenticated OAuth account before startup; OpenCode retains native tool ownership and Temper observes every permitted tool execution.
<!-- SECTION:FINAL_SUMMARY:END -->
