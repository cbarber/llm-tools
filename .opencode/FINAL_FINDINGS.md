# OpenCode Event Discovery - Final Findings

## Testing Environment
- OpenCode Version: 1.0.224 (latest)
- Plugin: `.opencode/plugin/temper/index.ts`
- Log: `/home/cbarber/src/llm-tools/.opencode/event.log`

## What Events Actually Fire

### ✅ tool.execute.before (bash only)
**Status:** WORKS
**Triggers:** Bash tool execution
**Data Structure:**
```json
{
  "input": {
    "tool": "bash",
    "sessionID": "ses_...",
    "callID": "toolu_..."
  },
  "output": {
    "args": {
      "command": "...",
      "description": "..."
    }
  }
}
```

### ❌ tool.execute.before (read/edit/write)
**Status:** DOES NOT FIRE
**Tested:** read, edit, write tools
**Result:** No events captured for any file operation tools

### ❌ tool.execute.after
**Status:** DOES NOT FIRE (or fails silently)
**Expected:** Should fire after tool completion
**Result:** No events captured despite handler being defined

### ❌ file.edited
**Status:** DOES NOT EXIST
**Confirmed:** Not in OpenCode source code (packages/plugin/src/index.ts)
**Docs:** Wrong/outdated

### ⚠️  Generic event handler
**Status:** CONFLICTS with specific handlers
**Issue:** Adding generic `event` handler breaks `tool.execute.before/after`
**Solution:** Use specific handlers only

## Source Code Analysis

From `https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/plugin/src/index.ts`:

**Available Hooks:**
- `event` (generic - conflicts with specific handlers)
- `config`
- `tool` (custom tool definitions)
- `auth`
- `chat.message` ✓
- `chat.params`
- `permission.ask`
- `tool.execute.before` ✓ (but only fires for bash)
- `tool.execute.after` (defined but doesn't fire)
- `experimental.*` hooks (compacting, etc.)

**NOT Available:**
- `file.edited` (docs are wrong)
- `file.watcher.updated` (docs mention but doesn't exist)
- Individual tool hooks for read/edit/write

## Critical Limitations

1. **No file operation events** - Can't hook read/edit/write tools
2. **Bash only** - tool.execute.before only fires for bash
3. **No after events** - tool.execute.after doesn't fire
4. **No file change events** - No way to detect when files are modified

## Implications for Workflow Hooks

**Original Plan (won't work):**
- Hook file.edited to show commit guidance ❌
- Hook tool.execute.before for edit/write to show guidelines ❌

**What's Actually Possible:**
- Hook bash commands only (git commit, git push, etc.) ✓
- Detect git operations through bash tool ✓
- Manual temper invocation ✓

**Recommended Approach:**
1. Hook `tool.execute.before` for bash
2. Detect git commands (commit, push, etc.)
3. Inject temper output for relevant git operations
4. Abandon automatic file-based hooks

## Next Steps

1. Design bash-only workflow hooks
2. Pattern match git commands in bash tool args
3. Call appropriate temper sections for git operations
4. Update AGENTS.md with bash-triggered workflow sections
