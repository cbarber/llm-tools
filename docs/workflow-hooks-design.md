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

### Phase 1: Extend Temper with New Sections

Add new workflow sections to AGENTS.md:

1. **`temper pre-edit`** - Show before file modifications
   - Extract and display Development Guidelines from AGENTS.md using existing logic
   - Show git status (staged, unstaged, untracked)
   - Simpler than Go: leverages existing temper pattern

2. **`temper post-edit`** - Show after file modifications, before commit
   - Display commit guidance (new or fixup?)
   - List uncommitted changes
   - Show commits since origin/main (for fixup context)
   - Simpler reminder, not complex heuristics

3. **`temper post-push`** - Show after git push
   - Detect PR association (branch tracking remote)
   - Display "📡 Subscribed to PR #N" message
   - Make PR subscription explicit in session

### Phase 2: OpenCode Plugin Integration

OpenCode plugins support `file.edited` events ([docs](https://opencode.ai/docs/plugins/#events)):

```typescript
// .opencode/plugin/workflow-hooks.ts
export const WorkflowHooks = async ({ $, directory }) => {
  return {
    "file.edited": async ({ path }) => {
      // Run temper post-edit after file modifications
      await $`temper post-edit`
    },
    
    "tool.execute.before": async (input, output) => {
      // Run temper pre-edit before edits
      if (input.tool === "edit" || input.tool === "write") {
        await $`temper pre-edit`
      }
    }
  }
}
```

This makes workflow hooks automatic for OpenCode - no manual invocation needed.

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

## Temper Sections (Workflow Hooks)

| Section | Agent Invocation | Purpose |
|---------|------------------|---------|
| `temper pre-edit` | Before file modification | Show guidelines from AGENTS.md, display git status |
| `temper post-edit` | After modification, before commit | Show commit guidance, uncommitted changes, commits since origin/main |
| `temper post-push` | After git push | Detect PR, display subscription message |

All sections follow existing temper pattern: extract from `## Workflow` in AGENTS.md.

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

2. **Extend temper with new sections** (1-2 hours)
   - Add `pre-edit`, `post-edit`, `post-push` commands
   - Follow existing `extract_subsection` pattern
   - No new abstractions needed

3. **Add AGENTS.md workflow sections** (1 hour)
   - Write `### pre-edit` section with guidelines extraction
   - Write `### post-edit` section with commit guidance
   - Write `### post-push` section with PR subscription

4. **Update forge for post-push hook** (30 min)
   - Detect PR number after push
   - Display "📡 Subscribed to PR #N"
   - Write `.git/pr-subscription` file

5. **Create OpenCode workflow-hooks plugin** (1-2 hours)
   - Hook `file.edited` event to run `temper post-edit`
   - Hook `tool.execute.before` for edit/write to run `temper pre-edit`
   - Package as `.opencode/plugin/workflow-hooks.ts`

6. **Testing** (1-2 hours)
   - Test each temper section manually
   - Validate PR subscription file creation
   - Measure impact on agent workflow

### Implementation Tasks

- llm-tools-dt3: Extend temper with three new sections (P1)
- llm-tools-qxq: Add workflow sections to AGENTS.md (P1)
- llm-tools-sly: Update forge for PR subscription tracking (P2)
- llm-tools-enu: Create OpenCode workflow-hooks plugin (P2) - updated scope after confirming file.edited event support

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
