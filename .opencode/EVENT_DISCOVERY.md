# OpenCode Event Discovery

This document guides the event discovery process needed to implement workflow hooks.

## Why Discovery First?

We can't write AGENTS.md sections without knowing:
1. What data OpenCode provides in each event
2. What the event structure looks like
3. How to match events to meaningful sections (e.g., "dev guidelines" not "tool.execute.before")

## Current Status

✅ Event logging plugin installed (`.opencode/plugin/temper/index.ts`)
✅ Logs events to `.opencode/event.log`

## Discovery Steps

### 1. Trigger Events

With OpenCode running, perform these actions:

**file.edited event:**
```bash
# Edit a file using OpenCode
# Agent uses Edit tool or Write tool
```

**tool.execute.before event:**
```bash
# Ask agent to edit or write a file
# Plugin logs event BEFORE tool executes
```

**tool.execute.after event:**
```bash
# Plugin logs event AFTER tool completes
```

### 2. Analyze Event Log

```bash
cat .opencode/event.log
```

Look for:
- Event structure (what fields are available?)
- Tool names (Edit, Write, Read, etc.)
- File paths
- Any metadata we can use for pattern matching

### 3. Design Pattern Matching Syntax

Based on event data, design AGENTS.md header syntax:

**Example ideas:**
```markdown
### dev guidelines (tool.execute.before Edit)
### dev guidelines (tool.execute.before Write)
### commit guidance (file.edited *.ts)
### commit guidance (file.edited)
```

Pattern should allow:
- Event type matching
- Tool name matching (for tool.execute.before)
- File pattern matching (optional)

### 4. Implement Pattern Matching

Once we know the syntax, implement:

1. **AGENTS.md sections** with patterns
2. **temper --event** with pattern matching logic
3. **Plugin** passes event data to temper

## Next Steps

After discovery:
- llm-tools-qxq: Add AGENTS.md sections with patterns
- llm-tools-enu: Implement pattern matching in plugin
- Test end-to-end workflow

## Event Log Location

`.opencode/event.log` (gitignored)
