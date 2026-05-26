---
name: backlog
description: Backlog.md task management — use when reading or updating project tasks
---

# backlog

Issue tracker for this project. Tasks live in `backlog/tasks/`.

## Key commands

```bash
backlog task list --status open          # list open tasks
backlog task list --status open --plain  # plain text (better for parsing)
backlog task create "Title" \
  --priority high|medium|low \
  --description "..."                    # create a task
backlog task <id>                        # view a task
backlog task update <id> --status done   # close a task
backlog task update <id> --description "..." --notes "..."
backlog board                            # Kanban view
backlog --help                           # full CLI reference
```

## Priority mapping

`high` = P1, `medium` = P2, `low` = P3/P4

## Notes

- `backlog/` directory must exist (`backlog init` to create)
- Task IDs are numeric prefixed strings, e.g. `1`
- Use `--plain` flag for script-friendly output
- Never edit task files directly — always use CLI (`backlog task edit`)
- Multi-line args: `\n` in quotes is literal; use `--append-notes` per line in sandboxed shells
