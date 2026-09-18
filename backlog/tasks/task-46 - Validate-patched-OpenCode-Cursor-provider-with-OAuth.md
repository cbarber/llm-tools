---
id: TASK-46
title: Validate patched OpenCode Cursor provider with OAuth
status: To Do
assignee: []
created_date: '2026-09-19 02:35'
updated_date: '2026-09-19 02:36'
labels: []
dependencies: []
priority: medium
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run the Nix-packaged open-cursor provider against a real Cursor OAuth session. Verify account model discovery, model switching, streamed read/edit/bash calls, Temper before/after triggers, unknown-tool fail-closed behavior, and normal ChatGPT prompting in the same OpenCode process.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OAuth-visible models appear in the OpenCode model picker
- [ ] #2 Cursor read, edit, and bash calls execute through OpenCode and fire Temper hooks
- [ ] #3 Unknown Cursor-native tools fail closed without side effects
- [ ] #4 ChatGPT prompting remains functional after Cursor use
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Record the tested Cursor and OpenCode versions and any discovered aliases or failures
<!-- DOD:END -->
