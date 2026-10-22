# Selected workflow decisions

Status: decisions reached through grilling, recorded for implementation.
Read [architecture](architecture.md) for the combined flow and
[program design](program-design.md) for the implementation pieces.
[Mojo policy](mojo.md) remains binding. Source research is linked from
[the collection index](../workflow.md); upstream instructions are not adopted wholesale.

## Select established pieces rather than a new methodology

| Area | Selection | Adaptation or boundary |
| --- | --- | --- |
| Work classification | Bounded and design-bearing paths | Depth follows consequential unresolved choices, not a file-count threshold. |
| Interview | Pocock's prerequisite-ready question frontier | Research facts before asking the user to decide; independent questions can share a round. |
| Product discussion | Dex's product-first guidance | Agree on problem, success evidence, and solution before technical design; out-of-scope items are specific ruled-out alternatives. |
| Technical design | Dex's system and program design | Separate human approvals; selective contracts, signatures, call trees, seams, and file responsibilities. |
| Implementation contract | Pocock's spec and tickets | Reference approved design; do not also generate Dex's structure outline. |
| Implementation progression | Pocock ticket dependencies with Dex-like sequential progression | One ticket at a time, not Pocock's maximum-concurrency frontier. |
| Implementation discipline | Mojo initialization, editing, commits, and history | Front-load instructions instead of event-triggered policy injection. |
| Review | Addy's fresh artifact-and-contract review | Review each slice and the integrated result; no mandatory cross-model offer every cycle. |
| Correction | Reviewer-authored SHA-targeted fixup proposals | Orchestrator accepts/rejects; this is a local adaptation, not Addy's prescribed role split. |
| Context renewal | Reasoned handoff plus in-place Claude compaction through Herdr | Use the current pane; no background-session/attach workflow. |

Poteto's concrete safety-proof approach remains useful to the less-front-loaded
bounded path. It is not a substitute implementation backbone for `implement-spec`
or `implement-outline`. General-purpose implementation and test-first technique
are different choices.

## Design approval permits learning, not silent overrides

- Early design's purpose is to surface consequential decisions sooner.
- Do not specify every implementation detail or freeze illustrative sketches.
- Implementers may fill in details left open.
- Overriding an agreed architecture or program decision requires human review again.
- Present the changed decision and consequences; review the whole affected section
  when its relationships change. Unaffected approvals remain valid.
- Keep the design document coherent rather than append a transcript of decisions.
- A context reset does not reopen approval or grant new authority.
- Confirm testing seams during the existing design discussion when practical.
  `to-spec` records the agreement and asks only for a missing decision.

## Implementation continues within approved scope

- Bounded work can be implemented in the main conversation.
- Planned multi-slice work uses a fresh implementer for each ticket, coordinated
  by the main conversation.
- Execute one ticket at a time. Finish verification and review/correction before
  advancing to the next unblocked ticket.
- Continue ordinary approved implementation without permission-to-proceed prompts.
- TDD is available when appropriate or requested, but invoking `tdd` is not
  mandatory for every ticket. Tickets specify behavior and verification requirements.
- Initialization includes agent/sandbox identification, Git state, and active work.
  Routine `forge pr status` and `forge pr next-action` are largely redundant with
  the work record; use Forge at actual PR interaction steps.

## Reviewers propose fixes; the orchestrator accepts them

- Review each meaningful slice and perform a final integrated review. For a bounded
  change, one review can serve both purposes.
- Every review has fresh context, through a subagent or separate agent session.
  Do not inherit the author's conversation as the reviewer's reasoning.
- Review the artifact against the agreed contract; reconcile findings against
  actual code and evidence rather than treating the reviewer as authoritative.
- Use Addy's simpler artifact review, not a restriction to the fix diff alone.
- Reviewers may author fixup commits targeting the owning SHAs. The orchestrator
  accepts or rejects them; reviewer proposals do not automatically enter the
  implementation branch.
- Verify accepted changes and obtain fresh-context re-review.
- Allow at most three correction rounds after the initial review, for both slice
  and final review. Unresolved substantive findings at the limit return to the user.
- Track rounds durably. Do not reset the count at compaction.
- Accepted fixups are folded into owning commits before publication. Preserve
  distinct atomic purposes, working retained history, and final human review/stamping.

## Continuation and renewal stay in the interactive workflow

- Stop's purpose is to keep an already-instructed agent moving when possible.
  It is not the mechanism for injecting editing or review policy at tool triggers.
- Load applicable skills at entry; reload them at recovery entry after renewal.
- Default to `/compact` in the current Herdr pane, backed by a reasoned handoff.
  This choice can change later.
- Missing or failed reasoned handoff pauses for human intervention. No blind
  compaction fallback is approved; observe failures before automating around them.
- The sandboxed agent never gets the Herdr socket: the agent is not trusted, and
  the socket would let it drive any pane. A helper outside the sandbox, started
  with Claude and exiting with it, owns all Herdr traffic for its own pane. The
  agent only writes a renewal request beside its work record; the helper treats
  it as untrusted, acts at most once per current handoff, and can submit only
  `/compact` and `/mojo-resume`. The request names its pane solely so a helper
  ignores other panes' requests; it is never a target.
- The helper executes only from the Nix store: its PATH is pinned. Herdr comes
  from a fixed path, `/run/current-system/sw/bin/herdr` unless the launching
  shell sets `HERDR_RENEW_HERDR`, never from PATH, which holds sandbox-writable
  directories. The helper starts only if every directory and symlink from `/`
  to the file, and the file, is owned by root and no directory is writable by
  others unless sticky. Lying in the Nix store proves nothing: the sandbox can
  build into it as a trusted Nix user.
- Herdr recognizes the sandboxed Claude by `HERDR_AGENT=claude`, which the Claude
  Code shell exports in a Herdr pane; Herdr reads process environments, as it
  does `HERDR_AGENT=opencode` for sandboxed OpenCode. Its Claude integration only
  reports session identity, which is not relayed.
- Waiting for a human decision and final human review are deliberate stops.
- A background Claude session followed by attach was rejected.
- Workspace/tab arrangement is organizational, not a context-renewal mechanism.
  Do not create a new tab or conversation for every sequential slice by default.

## Keep continuation state small and reference-rich

- Use one `work.json` in a durable home-directory work folder, with the active
  session pointing to it.
- Track current ticket/next action, any human gate, correction round, branch, and
  references to existing artifacts.
- Include agent/tool/session IDs so existing tooling can retrieve historical context.
- The coordinator advances progress after reconciling results. Workers return
  reports instead of independently advancing shared workflow state.
- Do not store a Herdr pane reference, commit ranges, or transcript paths.
- Do not build a transcript reader or recovery subsystem just to add reference links.
- Fixup SHAs belong to correction proposals; rejecting commit-range tracking in
  `work.json` does not remove SHA-targeted fixups from the engineering workflow.

## Front-load native Claude skills

- Use Claude's documented executable-skill syntax: inline `!` commands or fenced
  blocks opened with three backticks followed by `!`.
- Adapt the existing Mojo `{exec}` blocks for this Claude workflow; do not introduce
  a custom Markdown renderer or competing executable standard.
- Herdr submits the entry/resume skill invocation. Claude loads the skill and runs
  its executable initialization through the native mechanism.
- Personal language-style reference skills supply portable preferences; repository
  instructions and tool configuration take precedence. Select applicable guidance
  at entry for both implementers and fixup reviewers.

## Explicitly excluded or deferred

- No maintenance/debt register; concrete concerns become linked follow-up tickets.
- No exhaustive upfront specification or duplicated outline/ticket decomposition.
- No automatic override of agreed design, blind renewal, or agent final-human stamp.
- No mandatory TDD experiment was selected; the earlier question contrasting TDD
  with blast-radius as implementation alternatives was withdrawn.
- No wholesale adoption of Jesse's ledger machinery, five-round limit, or autonomous
  rulings; only the durable progress precedent is relevant.
- Thresholds, record naming, native API compatibility, and transport timing are
  implementation/validation details. They must not become an open-ended interview.
