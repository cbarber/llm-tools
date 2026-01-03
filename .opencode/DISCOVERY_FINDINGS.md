# OpenCode Event Discovery Findings

## What We Tested

Created event logging plugin that captures:
- `tool.execute.before`
- `tool.execute.after`  
- `file.edited`

## What We Learned

### ✅ tool.execute.before (bash)
- **Fires:** YES, for bash tool
- **Data structure:**
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

### ❌ tool.execute.before (read/edit)
- **Fires:** NO
- **Tested:** Used read and edit tools multiple times
- **Result:** No events captured

### ❌ file.edited
- **Fires:** NO
- **Tested:** Edited test-event-capture.md
- **Result:** No events captured

## Problems Discovered

1. **Duplicate logging:** Events logged twice (direct write + logEvent function)
2. **Limited tool coverage:** Only bash fires tool.execute.before
3. **file.edited doesn't fire:** May not exist or require different trigger

## Questions

1. Do read/edit tools fire different events?
2. Does file.edited only fire for certain file types?
3. Are there other events we should listen to?
4. Should we use tool.execute.after instead?

## Next Steps

1. Check OpenCode docs/source for complete event list
2. Try tool.execute.after to see if read/edit fire there
3. Consider alternative approach if file-based events don't exist
4. May need to rely solely on tool.execute.before (bash) for workflow hooks
