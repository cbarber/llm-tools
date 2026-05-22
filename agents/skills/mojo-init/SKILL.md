---
name: mojo-init
description: Initialize session with repo state and available work
once: true
triggers:
  - event: chat.message
---

# mojo-init

You are running in a sandboxed environment by default. The sandbox isolates filesystem access while allowing read-write to the current project directory and necessary git directories. Check `IN_AGENT_SANDBOX` environment variable to confirm sandbox status.

**Check repository state and pick work:**

```bash {exec}
if [[ -n "${OPENCODE:-}" ]]; then
  echo "Agent: OpenCode"
elif [[ -n "${CLAUDE_CODE:-}" ]]; then
  echo "Agent: Claude Code"
else
  echo "Agent: Unknown"
fi

if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  echo "Sandbox: enabled"
else
  echo "Sandbox: disabled"
fi

echo ""

echo "Git status:"
git status --short --branch

forge pr status

if command -v bd >/dev/null 2>&1 && [[ -d .beads ]]; then
  echo ""
  echo "📋 Available work:"
  bd ready --limit=5
fi

forge pr next-action
```

**Change only what is necessary.** Edit the minimum code required to accomplish the task. Do not rename variables, restructure functions, reformat blocks, or add comments unless that is the explicit goal.

**Preserve the original.** Treat existing code as deliberately written. If it works and is not the subject of the task, leave it exactly as it is.

**One concern per edit.** If you find yourself changing something "while you're in there," stop. That change belongs in a separate task.
