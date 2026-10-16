---
id: TASK-86
title: 'Handoff and resume hold up against edits, bad input and skipped steps'
status: To Do
assignee: []
created_date: '2026-10-16 18:50'
labels:
  - claude-code
  - follow-up
dependencies: []
references:
  - TASK-65
priority: low
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-65 review. Edits to the handoff file after linking are not detected (the fingerprint binds only the record). compact-resume exits 5 with a jq error on non-JSON input where other cases exit 0. Consuming the handoff on resume is enforced only by mojo-resume's instructions; skipping it leaves the handoff current and premature stops are let through. Empty writes (record .) count as stop-continue progress and reset its nudge bound.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A handoff edited after linking reads stale
- [ ] #2 compact-resume exits 0 on malformed input
- [ ] #3 Premature stops after a renewal are continued even if the consume step was skipped
<!-- AC:END -->
