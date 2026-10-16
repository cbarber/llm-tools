---
id: TASK-81
title: >-
  setup-settings handles first-run and odd settings files without aborting or
  going silent
status: To Do
assignee: []
created_date: '2026-10-16 18:16'
labels:
  - claude-code
  - follow-up
dependencies: []
references:
  - TASK-63
priority: low
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from TASK-63 review. Only the merge path warns and exits 0. On first run an unwritable .claude/ or a missing template aborts shell entry under set -e; an empty settings.local.json makes jq emit nothing, so no warning is printed and the base advances without applying anything; a symlinked settings.local.json is replaced by a regular file carrying the link's 777 mode.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 First run with an unwritable .claude/ or missing template warns and exits 0
- [ ] #2 An empty settings.local.json is warned about and the base is not advanced
- [ ] #3 A symlinked settings.local.json is updated through the link (or left alone with a warning), never replaced by a world-writable file
<!-- AC:END -->
