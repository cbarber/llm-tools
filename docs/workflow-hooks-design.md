# Workflow Hooks Architecture

## Problem Statement

Agents make non-atomic commits because there's no enforcement/guidance at critical workflow moments:

1. **Pre-Edit**: No reminder of guidelines or git status visibility
2. **Post-Edit**: No nudge to commit atomically or detect fixup candidates
3. **Post-Push/PR**: No explicit subscription message for PR notifications

Current bash tooling (`temper`, `forge`, `anvil`) is reactive - agents must remember to call them. This leads to:
- Non-atomic commits (mixing features/fixes/refactors)
- Unclear PR subscription state (notification routing issues)
- Manual recovery from broken git states

## Design Goals

### Workflow State Visibility
- Make workflow states explicit in session context
- Auto-inject relevant context at decision points
- Enable proactive guidance instead of reactive cleanup

### Atomic Commit Enforcement
- Detect multi-concern changes before commit
- Guide agents to split changes or use fixup commits
- Prevent mixed commits through workflow hooks

### PR Subscription Clarity
- Explicit "📡 Subscribed to PR #N" messages
- Visible in session context for routing decisions
- Auto-injected when pushing to PR branches

### Non-Interactive Operations
- No `-i` flags (agents can't handle interactive prompts)
- Structured output (JSON) for programmatic parsing
- Recoverable operations (clear rollback paths)

## Architecture Options

### Option 1: Enhanced Bash Tooling

**Approach:** Extend current bash scripts with hook system

**Pros:**
- Minimal rewrite of existing tools
- Quick to prototype
- Familiar to contributors

**Cons:**
- String manipulation complexity
- No structured state management
- Hard to test hooks in isolation
- Limited type safety

**Implementation:**
```bash
# Pre-edit hook
pre_edit() {
    echo "## Development Guidelines"
    # Use temper to extract specific section
    awk '/^## Development Guidelines$/,/^## [^#]/' AGENTS.md
    echo ""
    echo "## Current Git Status"
    git status --short
}

# Post-edit hook (commit guidance)
post_edit() {
    echo "## Commit Guidance"
    echo ""
    echo "Uncommitted changes:"
    git status --short
    echo ""
    echo "Commits since origin/main (for fixup context):"
    git log --oneline origin/main..HEAD
    echo ""
    echo "Commit as: new atomic commit or fixup to existing commit above"
}
```

### Option 2: Go-Based Workflow Engine (Overengineered)

**Approach:** New `workflows` tool in Go with MCP server integration

**Why not recommended:** MCP servers don't receive events proactively - agents must call them explicitly. Go engine adds complexity without solving the core problem of getting agents to invoke hooks at the right time.

**Pros:**
- Event-driven hook system
- Structured state (JSON/SQLite)
- Rich git operations (go-git library)
- Better testability (unit tests for hooks)
- Type safety for hook contracts
- MCP server for session integration

**Cons:**
- Higher upfront development cost
- New language in tooling stack
- Requires Nix packaging for Go

**Implementation:**
```go
// Hook interface
type Hook interface {
    Name() string
    Trigger() HookTrigger
    Execute(ctx WorkflowContext) error
}

// Workflow state
type WorkflowContext struct {
    GitStatus    GitStatusResult
    PRNumber     *int
    LastCommit   *Commit
    ChangedFiles []string
}

// Pre-edit hook implementation
type PreEditHook struct{}

func (h *PreEditHook) Execute(ctx WorkflowContext) error {
    // Show guidelines
    fmt.Println("## Development Guidelines")
    
    // Show git status
    fmt.Println("\n## Current Git Status")
    for _, file := range ctx.ChangedFiles {
        fmt.Printf("  M %s\n", file)
    }
    
    // Warn if uncommitted changes
    if len(ctx.ChangedFiles) > 0 {
        fmt.Println("\n⚠️  Uncommitted changes detected")
    }
    
    return nil
}
```

### Option 3: MCP Server Only

**Approach:** Lightweight MCP server wrapping current bash tools

**Pros:**
- Minimal code changes
- Leverages existing bash logic
- Easy MCP integration

**Cons:**
- Doesn't solve bash complexity issues
- Limited state management
- Still hard to test

## Recommended Approach

**Enhanced Temper: Extend bash tooling with new workflow sections**

Based on PR feedback, the simpler approach is extending `temper` with new workflow sections rather than building a Go engine. MCP servers don't receive events proactively, so hooks must be invoked explicitly by agents.

### Phase 1: Extend Temper with Event Arguments

Extend existing `temper` to accept event arguments instead of adding new commands:

**Usage:** `temper [section]` (existing) or `temper --event <event-name>` (new)

Using `--event` flag avoids conflating with existing section-based invocation.
Backwards compatible with `temper init`, `temper commit`, etc.

**Event-based invocation:**
- **`temper --event session.created`** - Session start (existing behavior via `temper init`)
- **`temper --event file.edited`** - After file modifications
- **`temper --event tool.execute.before`** - Before tool execution

Plugin passes OpenCode event names directly - no logic in plugin, all logic in temper.

### Phase 2: Extend Existing OpenCode Plugin

Existing plugin at `.opencode/plugin/temper/index.ts` already calls `temper init`.
Extend it to call `temper <event>` for file/tool events:

```typescript
// Extend .opencode/plugin/temper/index.ts
export const TemperPlugin: Plugin = async ({ client, $ }) => {
  return {
    "chat.message": async () => {
      // Existing: inject temper init at session start
      await injectTemperContext(client, $, sessionID)
    },
    
    "file.edited": async (event) => {
      // New: pass event directly to temper
      const output = await $`bash tools/temper --event file.edited`.text()
      // Log event data to understand shape: await Bun.write("/tmp/event.log", JSON.stringify(event))
    },
    
    "tool.execute.before": async (event) => {
      // New: pass event directly to temper
      const output = await $`bash tools/temper --event tool.execute.before`.text()
    }
  }
}
```

**Key principle:** Plugin is thin wrapper - just forwards events. All logic in temper for easier debugging.

### Phase 3: Simple PR Subscription Tracking

Post-push hook stores minimal state:
```bash
# After git push
PR_NUM=$(forge pr view --json | jq -r '.number // empty')
if [[ -n "$PR_NUM" ]]; then
    echo "📡 Subscribed to PR #$PR_NUM"
    # Store for anvil routing (simple file, not SQLite)
    echo "$PR_NUM" > .git/pr-subscription
fi
```

### Phase 4: Git-Absorb Research (Optional)

Investigate git-absorb for auto-fixup after core hooks proven valuable.

## Temper Events

| Invocation | OpenCode Event | Purpose |
|------------|----------------|---------|
| `temper init` or `temper --event session.created` | `session.created` (future) | Show workflow state |
| `temper --event file.edited` | `file.edited` | Show commit guidance after modifications |
| `temper --event tool.execute.before` | `tool.execute.before` | Show guidelines before edits |

Temper maps event name to AGENTS.md section: `## Workflow / ### <event-name>`

## Workflow State (Simplified)

No complex JSON schema. Simple file-based state:

```bash
# .git/pr-subscription (created by temper post-push)
13

# Read by anvil for PR routing
PR_NUM=$(cat .git/pr-subscription 2>/dev/null || echo "")
```

Minimal state = minimal complexity. No SQLite, no JSON parsing.

## Integration with Existing Tools

### Temper
- Add new sections: `pre-edit`, `post-edit`, `post-push`
- Each section extracts from `## Workflow` in AGENTS.md
- `post-push` writes `.git/pr-subscription` file
- No Go engine needed

### Forge
- `forge pr view` already shows PR number
- `temper post-push` uses this to detect subscription
- No new forge commands needed

### Anvil
- Read `.git/pr-subscription` for routing decisions
- Simple file read, no API calls
- Explicit subscription from temper post-push

## Development Plan

1. **Design validation** (this doc) ✅
   - ~~Review with stakeholders~~ PR #13 feedback received
   - ~~Validate hook triggers~~ Simplified to 3 sections
   - ~~Confirm Go vs Bash decision~~ Bash/temper extension wins

2. **Extend temper with --event flag** (30 min)
   - Add `--event <event-name>` flag (e.g., `file.edited`, `tool.execute.before`)
   - Map event name to AGENTS.md section: `## Workflow / ### <event-name>`
   - Backwards compatible with existing `temper init` section-based usage

3. **Add AGENTS.md workflow event sections** (1 hour)
   - Write `### file.edited` section with commit guidance
   - Write `### tool.execute.before` section with guidelines
   - Use OpenCode event names directly for simplicity

4. **Update forge for post-push hook** (30 min)
   - Detect PR number after push
   - Display "📡 Subscribed to PR #N"
   - Write `.git/pr-subscription` file

5. **Extend existing OpenCode temper plugin** (1 hour)
   - Add `file.edited` handler: `temper --event file.edited`
   - Add `tool.execute.before` handler: `temper --event tool.execute.before`
   - Log event data initially to understand structure
   - Thin wrapper - all logic in temper bash script

6. **Testing** (1-2 hours)
   - Test each temper section manually
   - Validate PR subscription file creation
   - Measure impact on agent workflow

### Implementation Tasks

- llm-tools-dt3: Add --event flag to temper, map to AGENTS.md sections (P1)
- llm-tools-qxq: Add event sections to AGENTS.md using OpenCode event names (P1)
- llm-tools-sly: Update forge for PR subscription tracking (P2)
- llm-tools-enu: Extend .opencode/plugin/temper/index.ts with thin event forwarding (P2)

## Success Metrics

- **Atomic commit rate**: Reduce non-atomic commits by 80%
- **PR subscription clarity**: 100% of PR pushes show subscription message
- **Agent recovery**: Eliminate broken git states from failed rebases
- **Developer experience**: Hooks provide value, not noise

## Open Questions

1. **Multi-concern detection**: Heuristics vs LLM-based analysis?
2. **Hook verbosity**: How much output is helpful vs noisy?
3. **State persistence**: JSON file vs SQLite?
4. **MCP server deployment**: Per-repo vs global?
5. **Git-absorb licensing**: Compatible with llm-tools?

## Related Work

- **llm-tools-txa**: Git-absorb research (P2)
- **llm-tools-8jk**: PR notification routing (completed, symptom fix)
- **llm-tools-y7q**: Jujutsu VCS research (P2)

## Next Steps

1. Finalize this design (review/feedback)
2. Create tasks for each development phase
3. Set up Go development environment in Nix
4. Prototype pre-edit hook to validate approach
