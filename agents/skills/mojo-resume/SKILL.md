---
name: mojo-resume
description: Resume coordinated work after context renewal (compaction) — reload the workflow skills, work record, and reasoned handoff, reconcile with Git, and continue only permitted work
---

# mojo-resume

Context was renewed. The conversation summary is not the source of truth:
the work record, the reasoned handoff, and Git are. Renewal never reopens an
approval and never clears a pending human gate.

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
elif ! record=$(work-record read 2>&1); then
  echo "$record"
else
  echo "$record"
  echo "Continuation: $(work-record check)"
  state=$(work-record handoff)
  handoff=$(jq -r '.artifacts | objects | .handoff | objects | .path | strings' <<<"$record")
  echo "Handoff: $state${handoff:+ ($handoff)}"
  if [[ "$state" == current ]]; then
    echo ""
    cat "$handoff"
    base=$(sed -n 's/^HEAD: //p' "$handoff" | head -n 1)
    echo ""
    if [[ -z "$base" ]]; then
      echo "Commits since handoff: unknown (no HEAD line in the handoff)."
    elif ! git rev-parse -q --verify "$base^{commit}" >/dev/null; then
      echo "Commits since handoff: handoff HEAD $base does not resolve."
    else
      echo "Commits since handoff ($base):"
      git log --oneline "$base..HEAD" || true
    fi
  fi
fi
```

## Resume

Act on the first case that applies:

1. **No record:** nothing is coordinated in this checkout. Say so and wait
   for the human.
2. **Inconsistent record:** report the problems and stop for the human to
   reconcile. Never overwrite it to make progress.
3. **Continuation `wait-for-human`:** present the pending gate verbatim, with
   the handoff if there is one, and stop. Do not clear, reword, or work
   around it; renewal is not an answer to it.
4. **Continuation `complete`:** present the work for final human review and
   stop.
5. **Handoff `missing` or `stale`:** the renewed context cannot tell what
   was in flight. Do not continue from the record alone. Pause durably, so
   the Stop hook does not continue the work either, then report what the
   record and Git show and stop:

   ```bash
   work-record record '.human_gate = $g' \
     --arg g "context renewed without a current handoff ($(work-record handoff)); confirm the next action before continuing"
   ```

6. **Handoff `current`:** resume.
   1. **Consume the handoff.** Its reasoning is now in this context. A
      current handoff tells the Stop hook to wait for renewal, so record a
      write before acting on it; any write makes the handoff stale, and the
      Stop hook continues the work again. A later renewal then needs a new
      handoff, or it pauses for the human. Confirm it prints `stale`:

      ```bash
      work-record record . >/dev/null
      work-record handoff
      ```

   2. **Reload skills.** Invoke each skill the handoff lists under _Skills
      to reload_ (`mojo-implement` when it lists none). Skill text carried
      over by compaction may be truncated and its initialization output is
      from before renewal, so invoke them again rather than recalling them.
   3. **Reconcile with Git.** Check the commits since the handoff and the
      working tree against the interrupted action. Commits from a worker
      the handoff names as running are expected; anything else unexplained
      is reconciled like a worker report before advancing, and a conflict
      Git does not settle becomes a `human_gate`.
   4. **Restore the interrupted action.** If the handoff names a running
      worker, wait for its result rather than dispatching another. Otherwise
      continue the record's `next_action` at the step the handoff describes,
      under the reloaded skill.
   5. **Stay within what was approved.** Decisions and approvals in the
      handoff stand. Work outside the approved scope still needs a
      `human_gate`.
