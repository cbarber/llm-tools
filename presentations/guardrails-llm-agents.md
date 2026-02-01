---
title: Engineering Rigor for LLM Agent Workflows
sub_title: From Magic to Methodology
author: Craig Barber
---

# The Day Everything Almost Disappeared

<!-- end_slide -->

Three Incidents, One Day
===

Let me tell you about the day an AI agent tried to delete critical parts of my system.

**Three times.**

<!-- end_slide -->

Incident #1: The Git Worktree Script
===

**Context:** Building a script to manage git worktrees

**What happened:**
```bash
git worktree add .docs docs
cd .docs
git rm -rf .  # "Clean up the worktree"
```

<!-- pause -->

**Result:** Entire local repository deleted

Fortunately everything was pushed. But local work-in-progress branches: gone.

<!-- pause -->

**Root cause:** Agent misunderstood context, tried to "help" with cleanup

<!-- end_slide -->

Incident #2: npm Debugging Gone Wrong
===

**Agent's logic chain:**

1. `npm install` fails
2. "Let me clean the cache to debug"
3. Cache cleaning fails
4. "Let me remove the problematic directory"

<!-- pause -->

**What it suggested:**
```bash
rm -rf ~/
```

<!-- pause -->

Caught in confirmation prompt. But one click away from disaster.

<!-- end_slide -->

Incident #3: Documentation Sync Script
===

**Agent's suggestion for orphan branch setup:**

```bash
git checkout --orphan docs
git reset --hard
rm -rf * .[^.]*  # "Remove all files except .git"
```

<!-- pause -->

**My response:**
> "That is the opposite of safe."

**Agent:**
> "You're absolutely right. I'm an idiot. That will delete untracked files."

<!-- pause -->

**The danger:** This was going into documentation for others to copy.

<!-- end_slide -->

The Pattern
===

**Each incident followed the same pattern:**

1. Reasonable initial goal
2. Small misunderstanding
3. Logical next step (given misunderstanding)
4. Another small error
5. **Catastrophe**

<!-- pause -->

**The problem isn't one big error.**

**It's small errors compounding.**

<!-- end_slide -->

# The Real Problem

<!-- end_slide -->

We're Treating LLMs as Magic
===

**Current approach:**

- Write good prompts
- Hope the agent follows them
- Confirm every command
- Fix mistakes manually

<!-- pause -->

**This isn't engineering. This is wishful thinking.**

<!-- pause -->

**Result:**
- Security exhaustion (clicking "yes" on every command)
- Can't automate (need human in loop)
- No measurement (can't improve what you can't measure)
- Cargo cult practices ("think step by step" because everyone does)

<!-- end_slide -->

Error Accumulation
===

**Small errors compound:**

- Each agent action: ~5% chance of subtle error
- Over 20 steps: (0.95)^20 = 36% success rate

<!-- pause -->

```
Steps    Success Rate
  1         95%
  5         77%
 10         60%
 20         36%
 50         8%
```

<!-- pause -->

**Without structural guardrails, failure is inevitable.**

<!-- end_slide -->

The Vision: Engineering Rigor
===

**What if we applied the same rigor to LLM workflows as traditional software?**

<!-- pause -->

- **Reproducibility** - Same environment, same results
- **Safety** - Structural constraints, not hope
- **Consistency** - Standards applied uniformly
- **Reviewability** - Human oversight that scales
- **Measurement** - Test hypotheses, iterate

<!-- pause -->

**This is how we build reliable systems.**

**Let's do it for LLM agents.**

<!-- end_slide -->

# The Framework

<!-- end_slide -->

Four Pillars of Rigor
===

**1. Reproducibility (Nix)**
Foundation - enables everything else

**2. Safety (Sandbox)**  
Structural protection from catastrophic failures

**3. Consistency (Workflow Injection)**
Standards applied uniformly across sessions

**4. Reviewability (SPR + Tools)**
Human review that scales

<!-- pause -->

**Together, these enable the scientific method for LLMs.**

<!-- end_slide -->

# Rigor #1: Reproducibility

<!-- end_slide -->

The "Works on My Machine" Problem
===

**Traditional agent setup:**

1. Install agent X (which version?)
2. Configure MCP Y (where's the config?)
3. Set up auth Z (which env var?)
4. Install tools A, B, C... (dependency hell)
5. Hope it works

<!-- pause -->

**Result:**
- 2+ hours onboarding
- "Works on my machine" syndrome
- Tool version mismatches
- Impossible to reproduce experiments

<!-- pause -->

**You can't do science without reproducibility.**

<!-- end_slide -->

Nix: Reproducible Environments
===

**One command:**
```bash
nix develop github:cbarber/llm-tools#opencode
```

<!-- pause -->

**What you get:**
- Agent (OpenCode/Claude Code)
- Sandbox (bubblewrap configured)
- Tools (spr, git-absorb, forge, beads)
- MCP servers (cclsp, language servers)
- Auth (API keys sourced)
- Workflow injection (hooks configured)

<!-- pause -->

**All:**
- Version-pinned (flake.lock)
- Reproducible (same on every machine)
- Isolated (won't break other projects)

<!-- end_slide -->

Why Nix Matters for Rigor
===

**Reproducible experiments:**
- Same tool versions across all tests
- No confounding variables from environment differences
- Results are replicable by others

<!-- pause -->

**Team-wide standards:**
- Everyone uses same configuration
- Updates propagate centrally
- Compliance enforced (e.g., OpenCode with sharing disabled)

<!-- pause -->

**Foundation for measurement:**
- Control the environment
- Isolate variables
- Run A/B tests reliably

<!-- pause -->

**Without reproducibility, you're not doing engineering.**

<!-- end_slide -->

Nix: The Learning Curve Question
===

**"Isn't Nix hard to learn?"**

<!-- pause -->

**Two answers:**

**For users:**
You don't need to know Nix. Just run the command.

**For distribution:**
We're a PR and CI away from Docker images that represent these shells.
No Nix knowledge required.

<!-- pause -->

**Trade-off:**
Upfront complexity for long-term reproducibility.

Worth it when you're building reliable LLM systems.

<!-- end_slide -->

# Rigor #2: Safety

<!-- end_slide -->

The Confirmation Fatigue Problem
===

**After the third rm -rf attempt, I realized:**

Confirmation dialogs don't scale.

<!-- pause -->

**Problems:**
- **Security exhaustion** - Eventually click "yes" automatically  
- **Blocks automation** - Can't run overnight/unsupervised
- **Trust erosion** - Constant vigilance required
- **One mistake = disaster** - Human error inevitable

<!-- pause -->

**We need structural safety, not human vigilance.**

<!-- end_slide -->

Sandbox: Structural Safety
===

**Bubblewrap isolation (Linux) / sandbox-exec (macOS)**

**Agent can access:**
- ✅ Current project directory (read/write)
- ✅ /nix store (read-only)
- ✅ Temporary workspace (read/write)

**Agent CANNOT access:**
- 🚫 HOME directory
- 🚫 /etc
- 🚫 Other projects
- 🚫 System directories

<!-- pause -->

**Key insight:** Whitelist (safe by default), not blacklist (try to catch everything).

<!-- end_slide -->

Sandbox: Live Demo
===

Let's see it in action:

```bash +exec
# Show we're in the project
echo "Current directory: $PWD"
echo "Sandbox status: ${IN_AGENT_SANDBOX:-not sandboxed}"
```

<!-- pause -->

Try to create file in home:

```bash +exec
touch ~/test-from-agent.txt 2>&1 || echo "✓ Blocked as expected"
```

<!-- pause -->

Try the dangerous command from incident #2:

```bash +exec
rm -rf ~/ 2>&1 || echo "✓ Sandbox protected!"
```

<!-- end_slide -->

Sandbox: Results
===

**Since enabling sandbox by default (2 months):**

- ✅ Zero security incidents
- ✅ Trust agents to run unsupervised
- ✅ No confirmation fatigue
- ✅ True automation possible

<!-- pause -->

**Company benefits:**
- Zero-trust by default
- Centralized compliance policy
- Safe experimentation environment

<!-- pause -->

**Safety enables experimentation.**

<!-- end_slide -->

# Rigor #3: Consistency

<!-- end_slide -->

The Guidelines Problem
===

**For months, I carefully wrote guidelines:**

```markdown
## Development Guidelines

* Always make atomic commits
* Commit after every edit
* Use conventional commit format
```

<!-- pause -->

**The agent ignored them.**

<!-- end_slide -->

Why Guidelines Get Ignored
===

**Example session timeline:**

```
Token 0-2K:    AGENTS.md loaded (includes guidelines)
Token 2K-10K:  User conversation, task description
Token 10K-30K: Code exploration, file reads
Token 30K-50K: Writing code, making changes
Token 50K:     Time to commit...
```

<!-- pause -->

**By token 50K:**
- Guidelines from token 500 are "lost in the middle"
- Recent code changes dominate (recency bias)
- Agent creates god commit mixing 3 concerns

<!-- pause -->

**Research:** "Lost in the Middle" (Liu et al., 2023)
- Performance degrades when info is in middle of context
- Highest performance: beginning or end
- Affects all LLMs, even long-context models

<!-- end_slide -->

Workflow Injection: Re-inject for Consistency
===

**The solution:**

Re-inject critical guidelines at decision points - at the END of context (high influence).

```
Agent edits file → file.edited event
                 ↓
         temper --event file.edited
                 ↓
    Extract guidelines from AGENTS.md
                 ↓
         Inject at end of context (fresh)
```

<!-- pause -->

**Key insight:** Don't rely on memory. Push context when needed.

<!-- end_slide -->

Workflow Injection: Before/After
===

**Before injection (agent's view at token 50K):**
```
[... 50,000 tokens of work ...]
(Guidelines from token 500 have minimal influence)
```

<!-- pause -->

**After injection (when file.edited fires):**
```
[... 50,000 tokens ...]

## Commit Guidance (FRESH CONTEXT)

Uncommitted changes:
  M src/sandbox.rs

Recent commits (for fixup context):
  abc123 feat(sandbox): add bubblewrap

Commit as: new atomic commit OR fixup to existing
```

<!-- pause -->

**Guidelines now have high attention weight RIGHT when needed.**

<!-- end_slide -->

Workflow Injection: Results
===

**Dogfooding over 3 months:**

**Before:** Regularly found god commits mixing concerns

**After:** Rarely see non-atomic commits

<!-- pause -->

**Important caveat:**
- This is anecdotal (for now)
- Experiments in progress for rigorous validation
- But subjective improvement is significant

<!-- pause -->

**Consistency enables reliable workflows.**

<!-- end_slide -->

# Rigor #4: Reviewability

<!-- end_slide -->

The God Commit Problem
===

**Typical agent commit:**

```
commit abc123

feat: add feature and fix bugs and refactor

- Implement new user authentication
- Fix typo in error message  
- Refactor database connection logic
- Update documentation
- Add tests
```

<!-- pause -->

**Problems:**
- Unreviewable (too many concerns)
- Unbisectable (can't isolate regressions)
- Unclear history (what was the actual goal?)

<!-- pause -->

**We still want to review agent code. We need reviewability.**

<!-- end_slide -->

Tools for Atomic Commits
===

**Atomic commits aren't one tool - they're a collection:**

- **spr** - Stacked PRs (one commit = one PR)
- **git-absorb** - Automatic fixup commits
- **forge** - Unified PR management (gh/tea wrapper)
- **temper** - Workflow injection trigger

<!-- pause -->

**Key insight:** These tools make it EASIER for the agent to follow our engineering standards.

<!-- pause -->

**All delivered via Nix** - reproducible tooling for consistent results.

<!-- end_slide -->

SPR: Stacked PRs
===

**Each commit becomes one PR:**

```bash
# Create atomic commits
git commit -m "feat(sandbox): add bubblewrap support"
git commit -m "test(sandbox): add test suite"
git commit -m "docs(sandbox): document usage"

# Create/update all PRs in stack
spr update

# View status
spr status
```

<!-- pause -->

**Benefits:**
- Small, focused PRs (reviewable)
- Independent review (don't wait for whole feature)
- Clear dependencies (stacked)
- Bisectable history

<!-- end_slide -->

SPR: What It Does (and Doesn't)
===

**Important clarification:**

SPR does NOT enforce atomic commits.

<!-- pause -->

**Enforcement comes from:**
- Workflow injection (reminders)
- Code review (human feedback)
- Tools making it easier (spr, git-absorb)

<!-- pause -->

**SPR's value:**
- Makes atomic commits *reviewable*
- Makes atomic commits *bisectable*  
- Makes atomic commits *easy to land*

<!-- pause -->

**Reviewability enables human oversight at scale.**

<!-- end_slide -->

PR Management: Closing the Loop
===

**Agents can't just throw code over the wall.**

They need to participate in code review.

<!-- pause -->

**Live demo:**

View PR and comments:

```bash +exec +id:pr_demo
# Simulating forge commands
echo "PR #123: Add sandbox support"
echo "Status: Open, 2 comments"
echo ""
echo "Comment from reviewer:"
echo "  Can you add a test for the HOME directory blocking?"
```

<!-- pause -->

Output appears here:
<!-- snippet_output: pr_demo -->

<!-- end_slide -->

PR Management: The Workflow
===

**Full cycle:**

1. Agent creates PR (`spr update`)
2. Human reviews, leaves comments
3. Agent reads: `forge pr comments 123`
4. Agent responds: `forge pr review-reply 123 456 "Fixed in abc123"`
5. Agent updates: `git commit --fixup + spr update`

<!-- pause -->

**Value:**
- Async collaboration (agent works while you're in meetings)
- Feedback loop closed (agent iterates on review)
- Human oversight maintained (we still review!)

<!-- pause -->

**Human review remains critical.**

<!-- end_slide -->

# The Scientific Method

<!-- end_slide -->

Infrastructure Enables Measurement
===

**What we've built:**

- ✅ Reproducible environments (Nix)
- ✅ Safe experimentation (Sandbox)
- ✅ Consistent application (Workflow injection)
- ✅ Human oversight (Reviewability)

<!-- pause -->

**Now we can actually do science:**

- Control environment (Nix)
- Run experiments safely (Sandbox)
- Measure outcomes (git history, metrics)
- Test hypotheses (A/B testing)
- Iterate based on evidence

<!-- pause -->

**From cargo cult to evidence-based engineering.**

<!-- end_slide -->

Experiments in Progress
===

**Hypothesis:** Workflow injection improves atomic commit rate

**Method:**
- Same tasks, with/without injection
- Measure: % atomic commits, commits per PR
- Control environment with Nix

<!-- pause -->

**Status:** Data collection underway

**Timeline:** Results before this presentation

<!-- pause -->

**This is what engineering rigor looks like:**

Test. Measure. Iterate.

<!-- end_slide -->

What We Can Test
===

**Now that infrastructure exists:**

- Does workflow injection improve adherence?
- Does guideline ordering matter?
- Is "think step by step" actually helpful?
- Which injection timing is optimal?
- Do the guardrails have interaction effects?

<!-- pause -->

**Before:** Guessing based on vibes

**Now:** Testing with controlled experiments

<!-- pause -->

**No more cargo culting.**

<!-- end_slide -->

# Discussion

<!-- end_slide -->

The Framework
===

**Four pillars of engineering rigor:**

1. **Reproducibility** - Nix provides foundation
2. **Safety** - Sandbox enables experimentation
3. **Consistency** - Injection ensures standards
4. **Reviewability** - Tools enable human oversight

<!-- pause -->

**Together:** Enable the scientific method for LLM workflows

<!-- pause -->

**Result:** Reliable, measurable, improvable systems

<!-- end_slide -->

Open Questions
===

**I want your skepticism.**

<!-- pause -->

**Challenge:**
- Where are the holes?
- What am I missing?
- What would change your mind?
- How should we test this properly?

<!-- pause -->

**Invitation to collaborate:**

This is early days. Help me design experiments, analyze results, pressure test assumptions.

<!-- end_slide -->

Thank You
===

**Questions? Challenges? Ideas?**

<!-- pause -->

**Resources:**
- Repo: `github.com/cbarber/llm-tools`
- Try it: `nix develop github:cbarber/llm-tools#opencode`

<!-- pause -->

**Let's build reliable LLM systems together.**

<!-- end_slide -->
