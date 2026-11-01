---
id: TASK-102
title: Claude agents cannot discover mojo-complete; OpenCode keeps it
status: In Progress
assignee: []
created_date: '2026-10-28 02:39'
updated_date: '2026-11-01 02:24'
labels:
  - follow-up
  - skills
dependencies: []
references:
  - TASK-99
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
mojo-complete pushes, force-pushes and pulls with rebase, which contradicts coordinator-only publishing. Its jobs in Claude now belong to the Stop hook, mojo-implement, mojo-review and mojo-handoff. OpenCode still triggers it through temper on session idle. Decision (human, 2026-10-31): the simplest fix that keeps OpenCode working is to make mojo-complete undiscoverable to Claude agents.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Claude Code sessions do not list or auto-invoke mojo-complete
- [x] #2 OpenCode's temper idle trigger still runs mojo-complete
- [x] #3 A test or documented check shows both
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
mojo-complete frontmatter sets disable-model-invocation: true (Claude drops its description from context and will not invoke it through the Skill tool, nor preload it into subagents) and user-invocable: false (hidden from the / menu); per code.claude.com/docs/en/skills. OpenCode ignores unknown frontmatter (opencode.ai/docs/skills) and temper parses only its own keys, so the idle trigger is unchanged: tests/test-mojo-complete.test.ts suite 2 (OpenCode, repo skills) still fires once; suite 3 asserts the flags.

AC1 needs a human check: enter nix develop .#claude-code (the shell entry re-syncs ~/.agents/skills), start a fresh Claude session, and confirm mojo-complete is absent from the model's skill list (ask it to list available skills) and from the / menu, and that asking it to run mojo-complete does not load the skill. Check AC1 and set Done if so.
<!-- SECTION:NOTES:END -->
