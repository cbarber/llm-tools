---
name: mojo-implement
description: Coordinate an approved backlog ticket breakdown — one ticket at a time through fresh implementers and fresh reviewers, reconciled and recorded
---

# mojo-implement

You coordinate the approved tickets for this checkout. You do not implement
them yourself: each ticket goes to a fresh implementer, you reconcile its
report against Git and the backlog, have it reviewed in fresh context, record
the outcome, and only then advance. One ticket reaches its reviewed result
before the next begins, and the integrated result is reviewed before you stop.

Coordination begins only after the human approved the ticket breakdown.
`/to-spec` and `/to-tickets` are user-invoked; never run them to manufacture a
ticket set.

**Checkout, work record, and approved tickets:**

```!
if [[ -n "${OPENCODE:-}" ]]; then
  echo "Agent: OpenCode"
elif [[ -n "${CLAUDECODE:-}" ]]; then
  echo "Agent: Claude Code"
else
  echo "Agent: Unknown"
fi

if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  echo "Sandbox: enabled"
else
  echo "Sandbox: disabled"
fi

echo "Checkout: $(git rev-parse --show-toplevel 2>/dev/null || pwd)"
echo "HEAD: $(git rev-parse --short HEAD 2>/dev/null || echo none)"
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
else
  echo "$record"
fi

echo ""
echo "Approved tickets, in approved order:"
top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if ! command -v backlog >/dev/null || [[ ! -f "$top/backlog/config.yml" ]]; then
  echo "No backlog in this checkout."
elif ! record=$(work-record read 2>/dev/null); then
  echo "No approved ticket set: the work record is missing or inconsistent."
elif ! tasks=$(cd "$top" && backlog task list --json 2>/dev/null); then
  echo "backlog task list failed; inspect the backlog before selecting a ticket."
else
  # Approved order lists blockers first, so the first open unblocked ticket
  # is the next one; backlog's isReady says whether its blockers are Done.
  jq -r --argjson r "$record" '
    (.tasks | map({key: (.id | ascii_upcase), value: .}) | from_entries) as $by
    | ($r.artifacts.tickets // []) as $ids
    | if ($ids | length) == 0 then "No approved ticket set recorded (artifacts.tickets is empty)."
      else
        [$ids[] | ascii_upcase | {id: ., t: $by[.]}] as $s
        | ($s | map(select(.t != null and .t.status != "Done"))) as $open
        | ($open | map(select(.t.isReady))) as $ready
        | (($r.current_ticket // "") | ascii_upcase) as $cur
        | ($s[] | if .t == null then "  \(.id)  not found"
            else "  \(.id)  \(.t.status)\(if .t.status == "Done" then "" elif .t.isReady then ", unblocked" else ", blocked" end)  \(.t.title)" end),
          (if $cur != "" and ($open | any(.id == $cur)) then "Next ticket: \($cur) (current ticket; reconcile any prior work before dispatching)"
           elif $cur != "" then "Current ticket \($cur) is closed but not yet reconciled; reconcile it before advancing."
           elif ($ready | length) > 0 then "Next ticket: \($ready[0].id) - \($ready[0].t.title)"
           elif ($open | length) == 0 and ($s | all(.t != null)) then "Next ticket: none; all \($s | length) approved tickets are Done."
           else "Next ticket: none; remaining tickets are blocked or missing: \($s | map(select(.t == null or .t.status != "Done") | .id) | join(", "))"
           end)
      end
  ' <<<"$tasks" || echo "Ticket selection failed; inspect the work record and backlog."
fi

echo ""
echo "Review scope:"
# The base lives in the scope's report, not the record, so it survives
# context renewal without the record holding a commit range.
if ! record=$(work-record read 2>/dev/null); then
  echo "  none: the work record is missing or inconsistent."
elif ! scope=$(jq -r '
    if .current_ticket then [.current_ticket, (.artifacts.reports[.current_ticket] // "")]
    elif .artifacts.reports.final then ["integrated result", .artifacts.reports.final]
    else empty end | @tsv' <<<"$record") || [[ -z "$scope" ]]; then
  echo "  none"
else
  IFS=$'\t' read -r name report <<<"$scope"
  round=$(jq -r '.correction_round' <<<"$record")
  base=$(sed -n 's/^Base: //p' "$report" 2>/dev/null | head -n 1)
  if [[ -z "$base" ]]; then
    echo "  $name: no review base recorded${report:+ in $report}; establish it before reviewing."
  elif ! git rev-parse -q --verify "$base^{commit}" >/dev/null; then
    echo "  $name: base $base does not resolve; reconcile before reviewing."
  else
    echo "  $name: base $base ($(git rev-list --count "$base..HEAD") commits to HEAD)"
  fi
  if ((round >= 3)); then
    echo "  Correction round: $round of 3; unresolved blocking findings go to the human."
  else
    echo "  Correction round: $round of 3"
  fi
fi
```

## Start or resume

- **Record present:** continue from its `next_action`. A `human_gate` is a
  deliberate stop: present it and wait. `complete` means agent work is done:
  present it for final human review and stop.
- **No record for this checkout:** if you were given the approved tickets (and
  any spec/design references), create the record, then invoke this skill again
  to load the selection:

  ```bash
  work-record init '.next_action = "select next ticket" | .artifacts.tickets = $t | .artifacts.spec = $s' \
    --argjson t '["TASK-1","TASK-2"]' --arg s "<spec or design reference>"
  ```

  List tickets in the approved order, blockers first. Without an approved
  ticket set, ask the human for it and stop.
- **Inconsistent record:** report the problems and stop for the human to
  reconcile. Never overwrite it to make progress.
- **No backlog:** this skill coordinates backlog tickets. Stop and say so.

## Run one ticket

1. **Select.** Take the `Next ticket` line. For a current ticket, inspect
   `git log` and `git status` for an earlier implementer's work first; if an
   implementer is still running, wait for it rather than dispatching another.
2. **Record the dispatch.** The ticket's report, beside the record, starts
   with its review base; the record links the report, never the base. Both
   commands keep an existing base and correction round, so re-dispatching
   unfinished work on the same ticket neither moves the base nor resets the
   round:

   ```bash
   report="$(dirname "$(work-record path)")/reports/TASK-N.md"
   mkdir -p "$(dirname "$report")"
   grep -q '^Base: ' "$report" 2>/dev/null || printf 'Base: %s\n' "$(git rev-parse HEAD)" >"$report"
   work-record record '.correction_round = (if .current_ticket == $t then .correction_round else 0 end)
     | .current_ticket = $t | .next_action = $a | .artifacts.reports[$t] = $r' \
     --arg t TASK-N --arg a "reconcile TASK-N implementer report" --arg r "$report"
   ```

3. **Choose pointers.** The ticket's references, spec/design links from the
   record, repository instructions (`CLAUDE.md`, `AGENTS.md`, formatter and
   linter configuration), and the personal language-style skills for the
   languages this ticket touches. Select only what applies.
4. **Dispatch a fresh implementer** with the Agent tool: a general-purpose
   subagent, never a `fork`, which would inherit this conversation. The prompt
   is the brief below; the brief is the only channel guaranteed to reach the
   implementer before its first edit, so it carries the standing rules itself
   and points at everything else. Wait for the report; do not edit the
   checkout or dispatch other work meanwhile.
5. **Reconcile** the report against actual state; do not trust it alone:
   - `git log --oneline <base>..HEAD` matches the reported commits, and
     `git status --short` shows no leftover changes from the implementer.
   - `backlog task TASK-N --plain` is Done with the satisfied criteria
     checked, and the ticket file changed in the commit that completes the
     work: `git log --oneline <base>..HEAD -- backlog/tasks`.
   - Each criterion has evidence; rerun a claimed check when the evidence is
     thin or surprising. Unproven items and concerns are weighed, not skipped.
   - Ordinary unfinished work within the ticket's scope: dispatch a fresh
     implementer with the brief plus a pointer to the earlier report and the
     gap, recorded with step 2's commands. A needed decision outside the
     approved scope: record a `human_gate` and stop.
6. **Review.** Append the implementer's report and your reconciliation to
   the ticket's report below its `Base:` line, then run _Review and
   correction_ below with the ticket as its scope. Advance only once no
   blocking finding remains.
7. **Record the outcome and advance.** Reload this skill afterwards to
   select the next ticket:

   ```bash
   work-record record '.current_ticket = null | .next_action = "select next ticket"
     | .agents += [{role: "implementer", ticket: $t, id: $id}]' \
     --arg t TASK-N --arg id "<agent id, if reported>"
   ```

Continue through the approved tickets without asking permission to proceed.

## Review and correction

A scope is one ticket, or the integrated result of the approved set. Its
`Review scope` line above shows its base and correction round; after context
renewal, continue from there rather than restarting. The scope's report holds
the findings, proposal decisions, and verification of every round.

- **Ticket:** base from its report's `Base:` line; contract is the ticket.
- **Integrated result:** base from its report's `Base:` line, copied from
  the first approved ticket's report on entry; contract is every approved
  ticket and the spec/design references.

A missing or unresolvable base is re-established from Git (the parent of the
scope's first commit) and written as the report's `Base:` line; when Git does
not settle it, record a `human_gate`.

`correction_round` counts correction rounds in the current scope: 0 is the
initial review. It changes only when a correction round or a new scope
begins; compaction, re-dispatch, and a new reviewer never reset it.

1. **Dispatch a fresh reviewer**, a general-purpose subagent with the
   reviewer brief below, never a `fork` and never a continued earlier
   reviewer. Give it the artifact and contract only: no implementer report,
   no reasoning from this conversation. Record
   `.next_action = "review <scope> round <r>"` and wait for its report.
2. **Reconcile findings** against the actual code, rerunning checks the
   evidence rests on. Spec gaps and Critical/Important findings block; Minor
   findings never enter the loop. A blocking finding the artifact refutes is
   recorded with that evidence and dropped. Write each finding and your
   decision to the scope's report.
3. **No blocking finding remains:** the scope passes. Create one follow-up
   ticket per Minor finding worth keeping, in one bulk commit
   (`backlog task create "<title>" -l follow-up --ref <TASK-N> -d "Follow-up
   from <TASK-N> review. ..."`), then return to where the scope came from.
4. **Blocking findings remain at round 3:** the bound is reached. Record
   `.human_gate = "<scope>: unresolved blocking findings after 3 correction
   rounds; see <report>"` and stop.
5. **Otherwise run a correction round:**
   1. **Count the round** before changing anything, so renewal mid-round
      resumes it rather than repeating it uncounted:
      `work-record record '.correction_round += 1 | .next_action = $a'
      --arg a "correct <scope> round <r+1>"`.
   2. **Inspect each proposal** without checking it out:
      `git show <fixup SHA>`. Accept it only if it fixes a confirmed blocking
      finding, stays inside the contract, and targets the owning commit with
      `fixup! <owning subject>`. A rejected proposal is never applied: the
      active checkout is untouched.
   3. **Apply** each accepted proposal in the active checkout with
      `git cherry-pick <fixup SHA>`. A confirmed blocking finding without
      an acceptable proposal goes to a fresh implementer (implementer brief
      plus the finding and its owning SHA) to fix with
      `git commit --fixup=<owning SHA>`.
   4. **Verify:** run the tests and reproduce the finding's failing
      scenario; it now passes. Drop what fails verification.
   5. **Fold** the fixups into their owning commits and confirm only history
      changed:

      ```bash
      before=$(git rev-parse HEAD) tree=$(git rev-parse 'HEAD^{tree}')
      GIT_SEQUENCE_EDITOR=: GIT_EDITOR=: git rebase -i --autosquash <base>
      [[ $(git rev-parse 'HEAD^{tree}') == "$tree" ]] && ! git log --format=%s <base>..HEAD | grep -q '^fixup! '
      ```

      Note `$before` in the scope's report for the re-reviewer's range-diff.
   6. **Clean up** each proposal worktree and branch:
      `git worktree remove <path>` and `git branch -D <proposal branch>`.
   7. **Re-review:** back to step 1 with a different fresh reviewer, the
      prior blocking findings, and
      `git range-diff <base>..<before> <base>..HEAD`.

Record each reviewer's agent id in `.agents` with `role: "reviewer"`.

## Stop

- **All approved tickets Done:** review the integrated result before
  completing. Entering the scope links its report and starts its own round
  count; re-entering it after renewal keeps both:

  ```bash
  report="$(dirname "$(work-record path)")/reports/final.md"
  first=$(work-record read | jq -r '.artifacts.reports[.artifacts.tickets[0] // "" | ascii_upcase] // ""')
  grep -q '^Base: ' "$report" 2>/dev/null || { grep -m 1 '^Base: ' "$first" 2>/dev/null || true; } >"$report"
  work-record record '.correction_round = (if .artifacts.reports.final then .correction_round else 0 end)
    | .artifacts.reports.final = $r | .next_action = "final integrated review"' --arg r "$report"
  ```

  Run _Review and correction_ with the integrated result as its scope. Once it
  passes, record completion and stop for final human review with a summary of
  tickets, commits, review outcomes, and open concerns:

  ```bash
  work-record record '.complete = true | .current_ticket = null | .next_action = null'
  ```

- **Remaining tickets blocked or missing:** record a `human_gate` naming them
  and stop.

## Implementer brief

Fill in the angle-bracketed pointers; keep the standing rules verbatim. Point
at artifacts; never paste this conversation.

```text
You are the implementer for backlog ticket <TASK-N> in the repository at
<checkout> (branch <branch>, base commit <base>).

Ticket: `backlog task <TASK-N> --plain`; its acceptance criteria are the
contract your work is reconciled against.
Design and spec: <references>
Earlier work: <reports or commits this ticket builds on, if any>
Guidance: <repository instructions and applicable style skills>

Before your first edit, load the Mojo discipline: invoke the mojo-edit-nudge
and mojo-commit skills (or read their SKILL.md under ~/.agents/skills) and
follow them. Minimal edits, one concern per commit, each commit
self-contained and working, prefactors as their own earlier commit.

Standing rules:
- Work only in this checkout. Do not push.
- Never `rm -rf` a whole shared directory (a skills directory, a record
  store) to change some of its contents; remove only what you created.
- Change tickets only with the backlog CLI, never by editing ticket files.
- End every commit message with mojo-commit's `Authored-By: <agent> (<model>)`
  trailer; forge finds unreviewed agent commits only by it, and a
  `Co-Authored-By` line does not replace it.
- Close the ticket in the commit that completes its work:
  `backlog task edit <TASK-N> --status Done --check-ac <n>` for each
  satisfied criterion, staged in that commit. Leave an unmet criterion
  unchecked and the ticket open, and say why.
- Do not write the coordinator's work record.
- End with a report: commits (SHA and subject) and what each changes;
  verification commands with their actual outcomes; each acceptance
  criterion with its evidence; anything unproven; decisions you made where
  the ticket left details open; concerns.
```

## Reviewer brief

Fill in the angle-bracketed pointers; keep the standing rules verbatim. Never
include the implementer's report or reasoning from this conversation.

```text
You are reviewing <the backlog ticket TASK-N | the integrated result of the
approved tickets> in the repository at <checkout> (branch <branch>).
Invoke the mojo-review skill and follow it.

Artifact: the commits <base>..HEAD.
Contract: `backlog task <TASK-N> --plain` for <each ticket>; design and spec:
<references>.
Guidance: <repository instructions and applicable style skills>
Round: <initial review | re-review after correction round r>
<Re-review only: prior blocking findings: <findings with evidence>; the fix
diff: `git range-diff <base>..<before> <base>..HEAD`.>
Proposal workspace: branch review/<scope>-r<r>, worktree
<scratch directory>/review-<scope>-r<r>.

Standing rules:
- Do not edit, commit, or switch branches in <checkout>; commit proposals
  only in your proposal worktree, as `git commit --fixup=<owning SHA>`.
- Do not push, change tickets, or write the work record.
- Never `rm -rf` a whole shared directory; leave your worktree and branch
  for the coordinator to remove.
- End with the mojo-review report: findings per axis with severity,
  evidence, and owning SHA; proposals; unproven claims; verdict.
```
