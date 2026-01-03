# OpenCode Plugin Events

Reference for OpenCode tool execution event hooks.

## Available Events

### tool.execute.before

Fires before all tool executions (bash, read, edit, write, etc.)

**Event data:**
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

**Available args by tool:**
- `bash`: `command`, `description`
- `edit`: `filePath`, `oldString`, `newString`
- `write`: `filePath`, `content`
- `read`: `filePath`

### tool.execute.after

Fires after all tool executions complete. Includes rich metadata.

**Event data:**
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
      "diff": "Index: /path/to/file.txt\n...",
      "filepath": "/path/to/file.txt"
    }
  }
}
```

**Additional metadata by tool:**
- `bash`: `output`, `exit` code
- `edit`: `diff` (unified format), `diagnostics`
- `write`: `diagnostics`
- `read`: `output` (file content)

## Not Available

- `file.edited` - Does not exist in OpenCode source
- `file.watcher.updated` - Does not exist

## Known Issues

**Generic event handler conflicts:** Adding a generic `event` handler breaks specific `tool.execute.before/after` handlers. Use specific handlers only.
