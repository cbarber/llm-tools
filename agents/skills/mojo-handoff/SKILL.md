---
name: mojo-handoff
description: Write a reasoned handoff for the current work and link it from the work record, so renewed context resumes it with mojo-resume
---

# mojo-handoff

Context is about to be renewed (compacted). Write the reasoning a fresh
context needs to continue this checkout's work and link it from the work
record. The handoff explains; the record, reports, tickets, and Git remain
the facts. Without a current handoff, renewal pauses for the human.

**Checkout, work record, and handoff:**

```!
echo "Checkout: $(git rev-parse --show-toplevel 2>/dev/null || pwd)"
echo "HEAD: $(git rev-parse HEAD 2>/dev/null || echo none)"
echo ""
echo "Git status:"
git status --short --branch || true

echo ""
echo "Work record:"
# A failing command aborts Claude's skill load, so a missing (3) or
# inconsistent (4) record is shown as state rather than exit status.
if ! command -v work-record >/dev/null; then
  echo "work-record is not on PATH."
elif record=$(work-record read 2>&1); then
  echo "$record"
  echo "Continuation: $(work-record check)"
  echo "Handoff: $(work-record handoff)"
  echo "Handoff file: $(dirname "$(work-record path)")/handoff.md"
else
  echo "$record"
fi
```

## Write the handoff

- **No record:** there is no coordinated work to hand off. Say so and stop.
- **Inconsistent record:** report the problems and stop; renewal must wait
  for the human to reconcile it.
- **Record present:** first record any progress you have already reconciled
  (`work-record record ...`), so the record's `next_action` and
  `human_gate` are what a fresh context should act on. Never clear or
  reword a pending `human_gate` to make renewal easier.

Then write the `Handoff file` above, replacing any earlier handoff. Point at
artifacts instead of copying them, and keep it short:

```markdown
# Handoff: <ticket or scope>

HEAD: <full SHA from above>

## Interrupted action
<What was in progress and how far it got: the skill and step, the worker
dispatched (agent id) and whether it is still running, the report or
proposal awaiting reconciliation. How to pick it up without repeating it.>

## Next action
<The record's next_action, and why it is next.>

## Human gate and approvals
<The pending gate verbatim, or "none". Approvals already given that a fresh
context must not reopen.>

## Decisions and reasoning
<Choices made in this context that no artifact records yet, with why.>

## Skills to reload
<The workflow skills to invoke on resume, e.g. mojo-implement.>

## References
<Record path, ticket ids, reports, design/spec, relevant commits.>

## Concerns
<Open doubts, or "none".>
```

## Link it

Link the file to the record as it now stands, and confirm it is current:

```bash
work-record handoff "$(dirname "$(work-record path)")/handoff.md" >/dev/null
work-record handoff
```

Linking binds the handoff to this record state: any later record update
makes it stale, and a stale handoff pauses the resumed context. So link
last, then stop: reply `Handoff ready: <file>` and take no further action
until context is renewed. If linking fails or does not print `current`,
say so and stop; renewal must not proceed on a failed handoff.
