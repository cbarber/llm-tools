---
id: TASK-44
title: Evaluate open-cursor for Cursor runtime
status: Done
assignee: []
created_date: '2026-09-18 02:46'
updated_date: '2026-09-18 21:33'
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
Verified the OpenCode-owned tool loop is the default; cursor-agent may still perform Cursor-native side effects before interception.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Integrated open-cursor 2.5.8 into the standard OpenCode Nix environment with cursor-agent, managed provider configuration, file credentials, and direct Cursor network routing.
<!-- SECTION:FINAL_SUMMARY:END -->
