---
id: TASK-61
title: Coordinator runs approved tickets in sequence
status: Done
assignee: []
created_date: '2026-10-16 02:43'
updated_date: '2026-10-16 04:03'
labels:
  - workflow
dependencies:
  - TASK-59
  - TASK-60
references:
  - docs/workflow/program-design.md
  - docs/workflow/architecture.md
  - docs/workflow/decisions.md
priority: high
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An implementation entry skill (adapted from Pocock's implement-spec with sequential progression) loads the workflow instructions, Mojo initialization, and the checkout's work record, then selects the next unblocked backlog ticket and dispatches a fresh implementer with ticket/design pointers, Mojo discipline, and applicable style guidance. The coordinator reconciles the implementer's report against actual Git and artifacts, records the outcome, closes the ticket in the commit that completes it, and advances. With no tickets remaining it stops for final human review. Documents that /to-spec and /to-tickets are user-invoked and that coordination begins only after the ticket-breakdown gate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each ticket is executed by a fresh implementer that receives pointers rather than pasted conversation
- [x] #2 Implementer instructions arrive before editing without a custom renderer
- [x] #3 The coordinator advances only after reconciling the report with Git and records progress in the work record
- [x] #4 Tickets are closed in the commit that completes their work
- [x] #5 Execution stops at final human review when no unblocked tickets remain
<!-- AC:END -->
