---
id: TASK-58
title: Expose Cursor ACP usage to Toad
status: To Do
assignee: []
created_date: '2026-09-27 23:43'
updated_date: '2026-09-27 23:43'
labels: []
dependencies: []
modified_files:
  - agents/cursor-cli/test-acp-startup.sh
priority: medium
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cursor CLI ACP 2026.06.19 completes prompts but emits no session/update with sessionUpdate=usage_update. The absence reproduces against raw cursor-agent and through sacp-conductor/Temper, while Toad 0.6.20 renders token and cost status only from that standard update. Track upstream Cursor ACP usage support or identify an authoritative usage source before adding any adapter.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-27: Extended agents/cursor-cli/test-acp-startup.sh with opt-in ACP_TEST_PROMPT and ACP_USAGE_GRACE. Raw cursor-agent --trust acp and the configured sacp-conductor/Temper chain both completed the minimal prompt and failed the usage_update assertion, including a two-second post-response grace window.
<!-- SECTION:NOTES:END -->
