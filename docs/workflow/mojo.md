# Binding Mojo policy

External workflow rules yield to these local skills. This is a summary; the
linked skill files remain authoritative. The user's final human review and
`Reviewed-By` stamp are an additional workflow constraint.

| Stage | Binding rule | Source |
| --- | --- | --- |
| Start | Establish agent, sandbox, repository, and PR state; inspect available next work. | [mojo-init](../../agents/skills/mojo-init/SKILL.md) |
| Edit | Make the minimum necessary change; preserve unrelated work; one concern per edit. | [mojo-edit-nudge](../../agents/skills/mojo-edit-nudge/SKILL.md) |
| Edit | Comments explain why and state one fact; place design rationale in ADRs. Make unavoidable side effects explicit; return early; delete obsolete code. | [mojo-edit-nudge](../../agents/skills/mojo-edit-nudge/SKILL.md) |
| Commit | Commit after editing. Each commit is self-contained, related, and fully functional. Every checkout in retained history is a valid stopping point. | [mojo-commit](../../agents/skills/mojo-commit/SKILL.md) |
| History | Review branch commits before pushing; fold fix-of-fix chains into their owning commits with fixup/autosquash. | [mojo-commit](../../agents/skills/mojo-commit/SKILL.md) |
| Rewrite | Interactive rebase and `amend!`/autosquash are supported tools. | [mojo-rebase](../../agents/skills/mojo-rebase/SKILL.md) |
| Create PR | Run relevant quality gates and update the tracker before publishing. Then create the PR without an extra confirmation. | [mojo-create-pull-request](../../agents/skills/mojo-create-pull-request/SKILL.md) |
| Update PR | Run gates and update the tracker before publication. Use force-with-lease only when reviewed history was rewritten; change PR description only for material scope changes. | [mojo-update-pull-request](../../agents/skills/mojo-update-pull-request/SKILL.md) |
| Respond | Address each finding with a focused change, run affected gates, preserve atomic history, and reply with the addressing commit. | [mojo-review-response](../../agents/skills/mojo-review-response/SKILL.md) |
| Collaborate | Use Forge to inspect PR state, comments, and next actions. | [mojo-pull-request](../../agents/skills/mojo-pull-request/SKILL.md), [mojo-init](../../agents/skills/mojo-init/SKILL.md) |

## Commit format

Use Conventional Commits with an imperative subject; aim for 50 characters,
without treating it as a hard cap. A subject joining purposes with “and <verb>”
signals a split. Add a body only for non-obvious rationale, breaking changes,
migrations, or issue references; wrap at 72 characters. Do not itemize the diff.
Include `Authored-By: <agent> (<model>)`. Avoid filler and first-person narration.

Atomic means a complete purpose, not the smallest diff. Temporary fixup commits
are folded before publication; distinct working changes keep distinct purposes.
Matt's non-green integration exception cannot authorize broken retained commits.
A wide refactor does not automatically require one final squash.

## Human review and tool behavior

Forge detects unstamped agent-authored commits and creates draft PRs;
GitHub's `needs-human-review` label is best-effort. PR polling checks local history
for `Reviewed-By` trailers and can promote a PR when detected authored commits
are stamped. Trailer presence is not evidence that a human reviewed the code,
that the stamped history was pushed, or that quality gates passed.

Sources: [Forge](../../tools/forge), [PR polling](../../tools/pr-poll).
The user owns the final intentional review/stamp. Do not infer approval from a
reviewer-agent verdict or tool status. Temper injects skill guidance; textual
quality requirements are not all mechanically enforced.
