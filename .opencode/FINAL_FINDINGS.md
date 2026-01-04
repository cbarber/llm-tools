# OpenCode Event Discovery - CORRECTED Findings

## Testing Environment
- OpenCode Version: 1.0.224 (latest)
- Plugin: `.opencode/plugin/temper/index.ts`
- Log: `/home/cbarber/src/llm-tools/.opencode/event.log`

## What Events Actually Fire

### ✅ tool.execute.before (ALL TOOLS)
**Status:** WORKS FOR ALL TOOLS
**Triggers:** bash, read, edit, write, and all other tool executions
**Data Structure:**

**Bash:**
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

**Write:**
```json
{
  "input": {
    "tool": "write",
    "sessionID": "ses_...",
    "callID": "toolu_..."
  },
  "output": {
    "args": {
      "filePath": "...",
      "content": "..."
    }
  }
}
```

**Edit:**
```json
{
  "input": {
    "tool": "edit",
    "sessionID": "ses_...",
    "callID": "toolu_..."
  },
  "output": {
    "args": {
      "filePath": "...",
      "oldString": "...",
      "newString": "..."
    }
  }
}
```

**Read:**
```json
{
  "input": {
    "tool": "read",
    "sessionID": "ses_...",
    "callID": "toolu_..."
  },
  "output": {
    "args": {
      "filePath": "..."
    }
  }
}
```

### ✅ tool.execute.after (ALL TOOLS)
**Status:** WORKS FOR ALL TOOLS
**Triggers:** After bash, read, edit, write, and all other tool executions complete
**Rich Data:** Includes file content, diffs (for edit), diagnostics, exit codes

**Edit tool after event includes full unified diff:**
```json
{
  "input": {
    "tool": "edit",
    "sessionID": "ses_...",
    "callID": "toolu_..."
  },
  "output": {
    "metadata": {
      "diagnostics": {},
      "diff": "Index: /path/to/file.txt\n===================================================================\n--- /path/to/file.txt\n+++ /path/to/file.txt\n@@ -1,1 +1,3 @@\n-old content\n+new content\n",
      "filepath": "/path/to/file.txt"
    }
  }
}
```

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

## Key Discovery

**PREVIOUS CONCLUSION WAS WRONG** due to broken logging (append mode not working).

After fixing the plugin logging bugs:
- ✅ Events fire for ALL tools (not just bash)
- ✅ Rich event data is available (file paths, content, diffs)
- ✅ Both before and after hooks work

## What IS Possible

**✅ Original workflow hooks plan CAN be implemented:**
- Pre-Edit Hook (tool.execute.before for edit/write) - Show development guidelines, git status
- Post-Edit Hook (tool.execute.after for edit) - Show commit guidance, detect fixup opportunities
- Post-Push Hook (bash tool "git push" pattern) - Subscribe to PR, display subscription status

**✅ Rich pattern matching capabilities:**
- Match by tool type (edit vs write vs read)
- Match by file path patterns (*.md vs *.ts)
- Access full event data (file content, diffs, command args)

**✅ Context-aware workflow injection:**
- Pass event data to temper for context-aware output
- Different guidance for different file types
- Detect git operations in bash commands

## Next Steps

1. ✅ Correct FINAL_FINDINGS.md (this file)
2. Create comprehensive event data reference with real examples from log
3. Design pattern matching system for mapping events to AGENTS.md sections
4. Create proof-of-concept: hook edit tool to inject simple workflow message
5. Reopen blocked beads issues (llm-tools-qxq, llm-tools-enu, llm-tools-sly)
6. Update workflow hooks design based on newly discovered capabilities
