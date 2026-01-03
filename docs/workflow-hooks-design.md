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
    echo "## Workflow Guidelines"
    grep "^## Development Guidelines" AGENTS.md
    echo ""
    echo "## Current Git Status"
    git status --short
}

# Post-edit hook (detect mixed concerns)
post_edit() {
    local changed_files=$(git diff --name-only)
    local concerns=0
    
    # Heuristic: count concern types by file patterns
    echo "$changed_files" | grep -q "\.md$" && ((concerns++))
    echo "$changed_files" | grep -q "\.sh$" && ((concerns++))
    echo "$changed_files" | grep -q "\.nix$" && ((concerns++))
    
    if [[ $concerns -gt 1 ]]; then
        echo "⚠️  Multiple concerns detected. Consider atomic commits:"
        echo "$changed_files"
    fi
}
```

### Option 2: Go-Based Workflow Engine (Recommended)

**Approach:** New `workflows` tool in Go with MCP server integration

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

**Hybrid: Go workflow engine + MCP server + bash tool integration**

### Phase 1: Core Workflow Engine (Go)
- Git operations library (go-git)
- Hook system with defined triggers
- State management (PR subscriptions, workflow context)
- JSON output for all operations

### Phase 2: Essential Hooks
1. **Pre-Edit Hook**
   - Show development guidelines (terseness, atomicity)
   - Display git status (staged, unstaged, untracked)
   - Warn about mixed concerns

2. **Post-Edit Hook**
   - Detect multi-concern changes (heuristics + LLM?)
   - Suggest commit or fixup
   - Show uncommitted change summary

3. **Post-Push Hook**
   - Detect PR association (branch tracking)
   - Display "📡 Subscribed to PR #N"
   - Store subscription in workflow state

### Phase 3: MCP Server Integration
- Expose workflow state to agents
- Hook invocation from agent context
- Auto-inject workflow messages

### Phase 4: Git-Absorb Integration
- Research git-absorb for auto-fixup
- Implement non-interactive fixup detection
- Integrate into post-edit hook

## Hook Triggers

| Hook | Trigger | Purpose |
|------|---------|---------|
| pre-edit | Before file modification | Show guidelines, git status |
| post-edit | After file modification | Detect mixed concerns, nudge commit |
| pre-commit | Before `git commit` | Validate atomic nature |
| post-commit | After `git commit` | Update workflow state |
| pre-push | Before `git push` | Check commit quality |
| post-push | After `git push` | Subscribe to PR, update state |

## Workflow State Schema

```json
{
  "current_branch": "feature/foo",
  "pr_subscriptions": [
    {
      "number": 12,
      "branch": "feature/foo",
      "subscribed_at": "2026-01-03T04:00:00Z"
    }
  ],
  "last_edit": {
    "timestamp": "2026-01-03T04:05:00Z",
    "files_changed": ["tools/forge", "AGENTS.md"],
    "concerns_detected": ["tooling", "docs"]
  },
  "commits_since_push": 2,
  "uncommitted_changes": true
}
```

## Integration with Existing Tools

### Temper
- Keep current workflow doc extraction
- Add hook invocation for workflow sections
- Call Go workflow engine for state queries

### Forge
- Add `forge pr subscribe` command
- Call Go workflow engine for PR state
- Integrate post-push hook

### Anvil
- Query workflow state for PR routing
- Subscribe to workflow state changes
- Route based on explicit subscriptions

## Development Plan

1. **Design validation** (this doc)
   - Review with stakeholders
   - Validate hook triggers
   - Confirm Go vs Bash decision

2. **Prototype Go engine** (1-2 days)
   - Basic hook system
   - Git status integration
   - JSON output

3. **Implement core hooks** (2-3 days)
   - Pre-edit, post-edit, post-push
   - Multi-concern detection
   - PR subscription tracking

4. **MCP server** (1-2 days)
   - Workflow state queries
   - Hook invocation
   - Session integration

5. **Git-absorb research** (1 day)
   - Evaluate for llm-tools workflow
   - Non-interactive usage
   - Integration approach

6. **Integration testing** (2-3 days)
   - Test with real agent sessions
   - Validate hook timing
   - Measure impact on commit quality

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
