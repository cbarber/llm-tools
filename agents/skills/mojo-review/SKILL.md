---
name: mojo-review
description: Review a ticket's commits, or the integrated result, in fresh context against its contract — Standards and Spec findings with evidence and severity, plus optional SHA-targeted fixup proposals in an isolated worktree
---

# mojo-review

You review an artifact against its contract in fresh context. You did not
write it and are not given the author's reasoning: judge only what the commits
and the contract show. You return a report; the coordinator decides what to do
with it. Never edit, commit, or switch branches in the checkout under review,
and never change tickets or the work record.

Adapted from the `code-review` skill: the same two axes, run as parallel
sub-agents, with the backlog ticket as the spec and severities that decide
whether a finding blocks.

**Checkout under review:**

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
# A failing command aborts Claude's skill load, so tolerate a non-repository.
git status --short --branch || true
echo ""
echo "Worktrees:"
git worktree list || true
```

## Inputs

The coordinator's brief names:

- **Scope:** one backlog ticket, or the integrated result of the approved set.
- **Fixed point:** the base commit; the artifact is `<base>..HEAD`.
- **Contract:** the ticket(s), read with `backlog task <id> --plain`, and the
  approved design/spec they reference.
- **Guidance:** repository instructions and applicable style skills.
- **Round:** initial review, or re-review after correction round N, with the
  prior blocking findings and a `git range-diff` command for the fix diff.
- **Proposal workspace:** a branch name and a scratch directory for fixups.

If the fixed point or contract is missing, report that and stop. Do not look
for the implementer's report or the coordinator's conversation.

## Process

### 1. Pin the fixed point

Capture the diff command once: `git diff <base>...HEAD`, and the commits via
`git log <base>..HEAD --oneline`.

Before going further, confirm the fixed point resolves
(`git rev-parse <base>`) and the diff is non-empty. A bad ref or empty diff
should fail here — not inside two parallel sub-agents.

### 2. Read the contract

The spec is the backlog ticket named in the brief — its description and
acceptance criteria — plus the design/spec documents it and the brief
reference. For an integrated review, it is every approved ticket together.
There is no separate issue tracker to consult.

### 3. Identify the standards sources

Repository instructions (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`),
formatter/linter/compiler configuration, established local patterns, the style
skills the brief names, and Mojo history policy: each commit self-contained,
related, and working, in Conventional Commits form (`mojo-commit`), with
minimal edits and one concern per change (`mojo-edit-nudge`).

On top of whatever the repo documents, the Standards axis always carries the
**smell baseline** below — a fixed set of Fowler code smells (_Refactoring_,
ch.3) that applies even when a repo documents nothing. Two rules bind it:

- **The repo overrides.** A documented repo standard always wins; where it endorses something the baseline would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic ("possible Feature Envy"), never a hard violation — and, like any standard here, skip anything tooling already enforces.

Each smell reads *what it is* → *how to fix*; match it against the diff:

- **Mysterious Name** — a function, variable, or type whose name doesn't reveal what it does or holds. → rename it; if no honest name comes, the design's murky.
- **Duplicated Code** — the same logic shape appears in more than one hunk or file in the change. → extract the shared shape, call it from both.
- **Feature Envy** — a method that reaches into another object's data more than its own. → move the method onto the data it envies.
- **Data Clumps** — the same few fields or params keep travelling together (a type wanting to be born). → bundle them into one type, pass that.
- **Primitive Obsession** — a primitive or string standing in for a domain concept that deserves its own type. → give the concept its own small type.
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type recurs across the change. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery** — one logical change forces scattered edits across many files in the diff. → gather what changes together into one module.
- **Divergent Change** — one file or module is edited for several unrelated reasons. → split so each module changes for one reason.
- **Speculative Generality** — abstraction, parameters, or hooks added for needs the spec doesn't have. → delete it; inline back until a real need shows.
- **Message Chains** — long `a.b().c().d()` navigation the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man** — a class or function that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest** — a subclass or implementer that ignores or overrides most of what it inherits. → drop the inheritance, use composition.

### 4. Spawn both sub-agents in parallel

Send a single message with two `Agent` tool calls. Use the `general-purpose`
subagent for both, never a `fork`. Each prompt includes the diff command, the
commit list, and the severity scale from step 5.

**Standards sub-agent prompt** — also include:

- The list of standards sources from step 3, **plus the smell baseline** pasted in full — the sub-agent has no other access to it.
- The brief: "Report — per file/hunk or commit where relevant — (a) every place the diff or its commit history violates a documented standard: cite the standard (file + the rule); and (b) any baseline smell you spot: name it and quote the hunk. Distinguish hard violations from judgement calls — documented-standard breaches can be hard, but baseline smells are always judgement calls, and a documented repo standard overrides the baseline. Skip anything tooling enforces. Give each finding a severity, its evidence, and the SHA of the commit that introduced it. Under 400 words."

**Spec sub-agent prompt** — also include:

- The ticket command(s) and design/spec paths from step 2.
- The brief: "Report: (a) acceptance criteria or requirements that are missing or partial; (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the criterion or spec line for each finding. Give each finding a severity, its evidence, and the SHA of the commit that introduced it. Under 400 words."

### 5. Reconcile and classify

Check each sub-agent finding against the actual code before reporting it, and
run cheap checks yourself (tests, the failing scenario) rather than assert.
Label what you could not prove as unproven. Every finding carries:

- **Severity:**
  - **Spec gap** — a criterion missing, partial, or implemented wrongly.
  - **Critical** — broken behaviour, data loss, a security exposure, or a
    commit that leaves the tree broken.
  - **Important** — a hard standards violation, a defect under normal use,
    or scope creep beyond the contract.
  - **Minor** — judgement calls, baseline smells, polish.
- **Evidence:** file and line or commit, with the quoted text or command output.
- **Owning commit:** the SHA in `<base>..HEAD` that introduced it.

Spec gaps and Critical/Important findings block. Minor findings are reported
but never block and never extend the correction loop.

### 6. Re-review only: judge the fix

On a re-review, the brief lists the prior blocking findings and a
`git range-diff` command showing what changed since the previous review. Mark
each prior finding resolved or unresolved with evidence. The range-diff
focuses the review; it does not limit it: review the whole artifact against
the contract again, and classify new findings with the same severities.

### 7. Propose fixups (optional)

For a blocking finding with a small, clear fix inside the contract, you may
propose a fixup. Only in the proposal worktree, never in the checkout under
review:

```bash
git worktree add -b <proposal branch> <scratch directory>/<worktree name> HEAD
cd <scratch directory>/<worktree name>
# minimal edit, then run the relevant checks
git commit --fixup=<owning SHA>
```

One fixup commit per finding and owning commit, made with `git commit
--fixup` (`-m`/`-F -` for any message, never an editor). Follow
`mojo-edit-nudge`: change only what the finding needs. Do not rewrite,
rebase, or push, and do not propose fixes for Minor findings. Leave the
worktree and branch for the coordinator to inspect and remove.

### 8. Report

Present the two axes under `## Standards` and `## Spec`, verbatim or lightly
cleaned. Do **not** merge or rerank findings across axes — the two axes are
deliberately separate (see _Why two axes_). Then:

```text
## Proposals
<finding> → fixup <SHA> on <proposal branch> targeting <owning SHA>; checks run and outcome

## Re-review (re-review only)
<prior finding>: resolved | unresolved — evidence

## Unproven
<claims you could not verify>

Verdict: blocking findings remain | no blocking findings
```

End with a one-line summary: total findings per axis by severity, and the
worst issue _within each axis_ (if any). Don't pick a single winner across
axes — that's the reranking the separation exists to prevent.

## Why two axes

A change can pass one axis and fail the other:

- Code that follows every standard but implements the wrong thing → **Standards pass, Spec fail.**
- Code that does exactly what the ticket asked but breaks the project's conventions → **Spec pass, Standards fail.**

Reporting them separately stops one axis from masking the other.
