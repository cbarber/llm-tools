# OpenCode Actual Events (from source code)

Source: https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/plugin/src/index.ts

## Available Hooks

### 1. event (catch-all)
```typescript
event?: (input: { event: Event }) => Promise<void>
```
**Generic event handler - might catch all events!**

### 2. config
```typescript
config?: (input: Config) => Promise<void>
```

### 3. tool (custom tools)
```typescript
tool?: {
  [key: string]: ToolDefinition
}
```

### 4. auth
```typescript
auth?: AuthHook
```

### 5. chat.message ✅ (we use this)
```typescript
"chat.message"?: (
  input: { sessionID: string; agent?: string; model?: { providerID: string; modelID: string }; messageID?: string },
  output: { message: UserMessage; parts: Part[] },
) => Promise<void>
```

### 6. chat.params
```typescript
"chat.params"?: (
  input: { sessionID: string; agent: string; model: Model; provider: ProviderContext; message: UserMessage },
  output: { temperature: number; topP: number; topK: number; options: Record<string, any> },
) => Promise<void>
```

### 7. permission.ask
```typescript
"permission.ask"?: (input: Permission, output: { status: "ask" | "deny" | "allow" }) => Promise<void>
```

### 8. tool.execute.before ✅ (we use this)
```typescript
"tool.execute.before"?: (
  input: { tool: string; sessionID: string; callID: string },
  output: { args: any },
) => Promise<void>
```

### 9. tool.execute.after ✅ (we use this)
```typescript
"tool.execute.after"?: (
  input: { tool: string; sessionID: string; callID: string },
  output: {
    title: string
    output: string
    metadata: any
  },
) => Promise<void>
```

### 10-13. experimental.* hooks
- `experimental.chat.messages.transform`
- `experimental.chat.system.transform`
- `experimental.session.compacting`
- `experimental.text.complete`

## KEY DISCOVERY: NO file.edited event!

The docs mention `file.edited` but **it doesn't exist in the actual source code**.

Available events are:
- Generic `event` (catch-all)
- `tool.execute.before`
- `tool.execute.after`
- Chat/message events
- Experimental hooks

## What This Means

1. **file.edited doesn't exist** - docs are wrong/outdated
2. **tool.execute.before/after are the only tool hooks**
3. **Generic `event` hook might catch everything** - we should test this!

## Next Step: Test Generic Event Hook

The `event` hook takes `{ event: Event }`. We need to:
1. Add generic event handler
2. Log ALL events that come through
3. See what events actually fire for read/edit/write
