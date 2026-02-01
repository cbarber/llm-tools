---
title: Guardrails for LLM Agent Workflows
sub_title: Building Reliability on Unreliable Components
author: Craig Barber
---

Today's Journey
===

**Part 1: The Problem** (15 min)
- Horror stories: When agents go wrong
- The compounding error problem
- Why confirmation dialogs fail

<!-- pause -->

**Part 2: The Insight** (10 min)
- Schmitt trigger analogy: Noise tolerance
- Recency bias in LLM context windows

<!-- pause -->

**Part 3: The Guardrails** (30 min)
- Sandbox: Preventing catastrophic failures
- Workflow injection: Fighting attention decay
- SPR: Enabling atomic workflows
- PR management: Closing the feedback loop
- Nix: Turnkey reproducibility

<!-- pause -->

**Part 4: The Path Forward** (5 min)
- From anecdote to evidence
- Scientific rigor for AI engineering

<!-- end_slide -->

# Part 1: The Problem

<!-- end_slide -->

The Day Everything Almost Disappeared
===

**Three incidents. One day.**

Let me tell you about the day an AI agent tried to delete critical parts of my system three times.

<!-- end_slide -->

Incident #1: The Git Worktree Script
===

**Context:** Building a script to manage git worktrees for documentation

**What happened:**
```bash
# Agent generated this:
git worktree add .docs docs
cd .docs
git rm -rf .  # "Clean up the worktree"
```

<!-- pause -->

**Result:** Entire local repository deleted

**Why it was bad:**
- Deletion was buried in script logic (easy to miss)
- Fortunately: Everything was pushed to remote
- But: Lost local work-in-progress branches

<!-- pause -->

**Root cause:** Agent misunderstood context, tried to "help" with cleanup

<!-- end_slide -->

Incident #2: The npm Debugging Attempt
===

**Context:** Debugging npm dependency issues

**Agent's logic:**
```
1. npm install fails
2. "Let me clean the cache to help debug"
3. npm cache fails  
4. "Let me remove the problematic directory"
```

<!-- pause -->

**What it suggested:**
```bash
rm -rf ~/
```

<!-- pause -->

**Result:** Caught in confirmation prompt

**Why it was terrifying:**
- Agent was trying to be helpful
- Each step seemed reasonable individually
- Compounding logic errors led to catastrophe

<!-- end_slide -->

Incident #3: The Documentation Sync Script
===

**Context:** Writing a script to sync documentation to orphan branch

**Agent suggested:**
```bash
# Setup for orphan branch
git checkout --orphan docs
git reset --hard
rm -rf * .[^.]*  # Remove all files except .git
```

<!-- pause -->

**My response:**
> "That is the opposite of safe. It actively deletes things."

**Agent's reply:**
> "You're absolutely right. I'm an idiot. That rm -rf will delete untracked files."

<!-- pause -->

**Why this matters:**
- Agent generated plausible but dangerous code
- Without understanding consequences
- In documentation meant to be copied by others

<!-- end_slide -->

The Pattern: Compounding Errors
===

**Each incident followed the same pattern:**

1. Agent has reasonable initial goal
2. Small misunderstanding of context
3. Logical next step (given misunderstanding)
4. Another small error
5. **Catastrophe**

<!-- pause -->

**The problem isn't one big error.**

**It's many small errors compounding.**

<!-- end_slide -->

Why Confirmation Dialogs Fail
===

**After the third attempt, I realized:**

Confirmation dialogs don't scale.

<!-- pause -->

**Problems with confirmation:**

1. **Security exhaustion** - Fatigue leads to clicking "yes" automatically
2. **Blocks automation** - Can't run agents overnight/unsupervised
3. **Trust erosion** - Constant vigilance required
4. **False sense of security** - One missed click = disaster

<!-- pause -->

**We need a better solution.**

<!-- end_slide -->

Pain Point #2: Attention Decay
===

**For months, I carefully wrote guidelines in AGENTS.md:**

```markdown
## Development Guidelines

* Be succinct. Only provide examples if necessary
* Be strategic. Plan first, ask questions, then execute
* Always make atomic commits
* Commit after every edit
```

<!-- pause -->

**The agent ignored them.**

<!-- end_slide -->

The Aha Moment
===

**Then I learned about how LLMs use long contexts.**

The key insight: **Position bias - "Lost in the middle"**

<!-- pause -->

**What research shows:**

- LLMs have 200K+ token context windows
- But performance degrades based on position
- Information at start or end is most accessible
- Information in the middle is often "lost"
- My guidelines at the start get buried by context

<!-- pause -->

**It's not that the agent is dumb.**

**It's that my guidelines from the start are competing with recency bias and 50K tokens of intervening context.**

<!-- end_slide -->

The Guidelines Problem
===

**Example session timeline:**

```
Token 0-2K:    AGENTS.md loaded (includes "make atomic commits")
Token 2K-10K:  User conversation, task description
Token 10K-30K: Code exploration, file reads
Token 30K-50K: Writing code, making changes
Token 50K:     Time to commit...
```

<!-- pause -->

**By token 50K:**
- Guideline from token 500 is "lost in the middle"
- Recent code changes are at the end (high influence)
- Agent creates "god commit" mixing 3 concerns
- Despite clear guidelines against it

<!-- pause -->

**Research: "Lost in the Middle" (Liu et al., 2023)**
- Performance degrades when relevant info is in middle of context
- Highest performance: beginning or end of context
- This affects even long-context models

<!-- end_slide -->

Research: Lost in the Middle
===

**"Lost in the Middle: How Language Models Use Long Contexts"**
*Liu et al., 2023 - Transactions of the Association for Computational Linguistics*

<!-- pause -->

**Key findings:**

Performance degrades significantly when relevant information is in the middle of long contexts.

<!-- pause -->

**Position matters:**
- **Beginning of context**: High performance
- **Middle of context**: Significant degradation  
- **End of context**: High performance (recency bias)

<!-- pause -->

**Implication for my AGENTS.md:**

Guidelines at the start get "lost in the middle" as context grows.

By token 50K, they're buried and have minimal influence on decisions.

<!-- end_slide -->

Pain Point #3: Non-Atomic Commits
===

**Typical agent commit without guardrails:**

```
commit abc123
Author: agent

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
- Unbisectable (can't isolate which change caused regression)
- Unclear history (what was the actual goal?)
- Manual cleanup required (splitting commits post-hoc)

<!-- end_slide -->

# Part 2: The Core Insight

<!-- end_slide -->

The Schmitt Trigger Analogy
===

**I started thinking about this as a noise tolerance problem.**

<!-- 
speaker_note: |
  Live demo planned - Audio to square wave conversion.
  Backup - pre-recorded visualization available.
-->

<!-- pause -->

**Concept:**
- **Clean signal** → Success (agent follows workflow)
- **Noisy signal** → Small errors at each step
- **Without hysteresis** → Noise causes immediate failure
- **With hysteresis (guardrails)** → Noise is absorbed

<!-- end_slide -->

The Model: Square Wave States
===

```
Success State (Peak)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    
                    ↕ Noise (small errors)
                    
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Failure State (Valley)
```

<!-- pause -->

**Without guardrails:**
- Small error → instant state collapse
- Valley is wide (easy to fall into)
- Peak is narrow (hard to maintain)
- No recovery mechanism

<!-- pause -->

**With guardrails (hysteresis):**
- Must accumulate errors to fail (upper threshold)
- Must accumulate successes to recover (lower threshold)
- Peak is wide (stable success state)
- Valley is narrow (hard to fall into)

<!-- end_slide -->

Why This Model Works
===

**Each agent action introduces small probability of error:**

- Misunderstanding context (5%)
- Incorrect assumption (3%)
- Off-by-one error (2%)
- Wrong tool selection (4%)

<!-- pause -->

**Over a 20-step workflow:**
- Without guardrails: Errors compound
- Each mistake makes next mistake more likely
- Eventually → catastrophic failure

<!-- pause -->

**With guardrails:**
- Small errors are caught early
- Structural constraints prevent compounding
- System stays in success state despite noise

<!-- end_slide -->

Guardrails Create Hysteresis Bands
===

**Upper threshold (success → failure):**
- Agent would need multiple severe errors
- Sandbox blocks catastrophic commands
- Workflow injection reminds of standards
- Hard to leave success state

<!-- pause -->

**Lower threshold (failure → success):**
- Clear recovery paths
- Fixup commits for mistakes
- Git operations are non-interactive
- Easy to return to success state

<!-- pause -->

**Result: Stable success basin**

<!-- end_slide -->

# Part 3: The Guardrails

<!-- end_slide -->

Guardrail #1: Sandbox Everything
===

**The solution: Bubblewrap isolation**

**What the agent can access:**
- ✅ Current project directory (read/write)
- ✅ /nix store (read-only)
- ✅ Temporary workspace /tmp/agent-work (read/write)

<!-- pause -->

**What the agent CANNOT access:**
- 🚫 HOME directory
- 🚫 /etc
- 🚫 Other projects
- 🚫 System directories

<!-- end_slide -->

Sandbox Demo
===

<!-- 
speaker_note: |
  Switch to sandboxed agent shell for live demo.
  Show PWD, attempt to touch ~/test.txt, attempt rm -rf ~/ 
-->

```bash
# Inside sandbox - show current location
echo $PWD
# /home/user/src/llm-tools (works)

# Try to access home directory
touch ~/test.txt
# Permission denied (blocked)

# Try the dangerous command from incident #2
rm -rf ~/
# Permission denied (safe!)
```

<!-- pause -->

**Key point: The agent can't accidentally nuke the system even if it tries.**

<!-- end_slide -->

Sandbox Implementation
===

**Technology: Bubblewrap (Linux) / sandbox-exec (macOS)**

```bash
# What happens under the hood
bwrap \
  --ro-bind /nix /nix \
  --bind $PROJECT_DIR $PROJECT_DIR \
  --tmpfs /tmp \
  --unshare-all \
  --share-net \
  --die-with-parent \
  -- command args...
```

<!-- pause -->

**Architecture:**
- User namespaces (no root required)
- Selective bind mounts
- Automatic cleanup on exit
- Network enabled (for API calls)

<!-- end_slide -->

Sandbox: Dogfooding Results
===

**Since enabling sandbox by default (2 months ago):**

- ✅ **Zero security incidents**
- ✅ **Trust agents to run unsupervised**
- ✅ **No confirmation fatigue**
- ✅ **Enables true automation**

<!-- pause -->

**Company benefits:**
- Zero-trust by default
- No security exhaustion
- Centralized security policy (via Nix)
- Audit trail (all filesystem access logged)

<!-- end_slide -->

Guardrail #2: Workflow Boundary Injection
===

**The problem revisited:**

Guidelines at the start of AGENTS.md get "lost in the middle" by mid-session.

<!-- pause -->

**The solution:**

Re-inject critical context at decision points - at the END of context (high influence position).

```
Agent edits file → file.edited event fired
                 ↓
         temper --event file.edited
                 ↓
    Extract relevant section from AGENTS.md
                 ↓
         Inject into agent context (fresh)
```

<!-- end_slide -->

Architecture: Event-Driven Re-Injection
===

```
OpenCode Plugin
    ↓
  (event fired: file.edited)
    ↓
temper --event file.edited
    ↓
Extract: ## Workflow / ### file.edited from AGENTS.md
    ↓
Show: commit guidelines, git status, fixup candidates
    ↓
Agent context (fresh, high attention weight)
```

<!-- pause -->

**Key principle:**
- Don't rely on agent memory
- Push context when it's needed
- Fresh context = high attention weight

<!-- end_slide -->

Workflow Injection Example
===

**Before injection (agent's view at token 50K):**
```
[... 50,000 tokens of code and conversation ...]
(Guidelines from token 500 have ~0% influence)
```

<!-- pause -->

**After injection (when file.edited fires):**
```
[... 50,000 tokens ...]

## Commit Guidance (FRESH CONTEXT)

Uncommitted changes:
  M src/sandbox.rs
  M tools/agent-sandbox.sh

Recent commits (for fixup context):
  abc123 feat(sandbox): add bubblewrap support
  def456 test(sandbox): add test suite

Commit as: new atomic commit OR fixup to existing commit above
```

<!-- pause -->

**Agent now has relevant context with high attention weight.**

<!-- end_slide -->

Injection vs Skills: Complementary Tools
===

**Claude Skills:**
- Pull-based (agent must request)
- Deep reference for complex procedures
- Good for: Rarely-used workflows, detailed howtos

<!-- pause -->

**Workflow Injection:**
- Push-based (automatic at decision points)
- Brief reminders for critical path
- Good for: Frequent operations, standards enforcement

<!-- pause -->

**Analogy:**
- **Skills** = Reference manual on the shelf
- **Injection** = Pop-up reminder when you're about to make a mistake

<!-- pause -->

**They solve different problems and work together.**

<!-- end_slide -->

Workflow Injection: Dogfooding Results
===

**Subjective observations over 3 months:**

Before injection:
- Regularly found god commits mixing concerns
- Manual cleanup required frequently
- Forgotten workflow standards mid-session

<!-- pause -->

After injection:
- Rarely see non-atomic commits
- Workflow standards followed consistently
- Less manual intervention needed

<!-- pause -->

**Important caveat:**
- This is anecdotal evidence
- No rigorous A/B testing yet
- But subjective improvement is significant
- Rigorous measurement is next (see Part 4)

<!-- end_slide -->

Workflow Injection: Open Question
===

**Hypothesis to test:**

Skills alone won't provide the same benefit as automatic injection.

<!-- pause -->

**Experiment design:**
1. Create skill with same content (commit guidelines)
2. Run 10 sessions with skill available but injection disabled
3. Measure: Does agent naturally call skill? When? Consistency?
4. Run 10 sessions with injection enabled (no skill)
5. Compare: Atomic commit rates, workflow adherence

<!-- pause -->

**Expected result:**
- Agent won't call skill consistently
- Injection will have higher adherence
- Validates push-based approach

<!-- pause -->

**Status: Planned but not yet executed**

<!-- end_slide -->

Guardrail #3: SPR for Atomic Workflows
===

**Even with workflow injection nudging toward atomic commits...**

**We need tooling that makes atomic commits *easy*.**

<!-- pause -->

**Solution: Stacked PRs with spr**

- Each commit → one PR
- PRs stack on each other (dependencies clear)
- Independent review
- Independent landing

<!-- end_slide -->

SPR Workflow
===

**The workflow:**

```bash
# Create atomic commits
git commit -m "feat(sandbox): add bubblewrap support"
git commit -m "test(sandbox): add test suite"
git commit -m "docs(sandbox): document usage"

# Create/update all PRs in stack
export GITHUB_TOKEN=$(cat ~/.config/nixsmith/github-token)
spr update

# View PR status with checks/approvals
spr status

# Merge entire approved stack
spr merge
```

<!-- end_slide -->

SPR Example Output
===

<!-- 
speaker_note: |
  Demo spr workflow on real branch.
  Show spr update, spr status with stacked PRs.
-->

```
$ spr status

✓ #123 feat(sandbox): add bubblewrap support
  Checks: ✓ CI passed
  Reviews: ✓ Approved by alice
  
⧗ #124 test(sandbox): add test suite
  Stacks on: #123
  Checks: ⧗ CI running
  Reviews: (awaiting review)
  
⧗ #125 docs(sandbox): document usage
  Stacks on: #124
  Checks: ⧗ Queued
  Reviews: (awaiting review)
```

<!-- pause -->

**Each PR is:**
- Small (focused on one change)
- Reviewable (clear purpose)
- Independent (can be approved separately)

<!-- end_slide -->

SPR: What It Does (and Doesn't Do)
===

**Important clarification:**

SPR does NOT enforce atomic commits.

<!-- pause -->

**Agent can still create:**
```
commit abc123
- Add feature X
- Fix bug Y
- Refactor Z
```

SPR just makes it one PR per god commit.

<!-- pause -->

**What enforces atomicity:**
- Workflow injection (reminds of standards)
- Pre-commit hooks (detects multi-concern commits)
- Code review (human feedback)

<!-- pause -->

**SPR's value:**
- Makes atomic commits *reviewable*
- Makes atomic commits *bisectable*
- Makes atomic commits *easy to land*

<!-- end_slide -->

SPR: Dogfooding Results
===

**Observations:**

- PR review time decreased (smaller, focused PRs)
- Reviewers can approve incrementally (don't wait for whole feature)
- Git history is cleaner (each commit is meaningful)
- Bisect works reliably (each commit is self-contained)

<!-- pause -->

**Company benefits:**
- Same review standards for agent/human code
- Reviewers stay sane (no 1000-line PRs)
- Clear rollback paths (revert single commit)
- Better collaboration (agents work like team members)

<!-- end_slide -->

Guardrail #4: PR Management in Session
===

**Agents can't just throw code over the wall.**

**They need to participate in code review.**

<!-- pause -->

**The workflow:**

```bash
# Agent creates PR
spr update

# Reviewer (human or agent) leaves comments
# Agent reads feedback
bash tools/forge pr comments 123

# Agent responds in-session
bash tools/forge pr review-reply 123 456 "Fixed in abc123"

# Agent addresses feedback
git commit --fixup=abc123
git rebase --autosquash origin/main

# Agent updates PR
spr update
```

<!-- end_slide -->

PR Management Demo
===

<!-- 
speaker_note: |
  Demo forge pr view, pr comments, pr review-reply commands.
-->

```bash
# View PR details
bash tools/forge pr view 123

# Read review comments
bash tools/forge pr comments 123

# Reply to specific comment
bash tools/forge pr review-reply 123 456 \
  "Fixed the race condition in commit def789"

# Check status
spr status
```

<!-- pause -->

**Key insight: The agent is part of the team.**

It responds to feedback just like any engineer.

<!-- end_slide -->

PR Management: Value
===

**Benefits:**

- **Async collaboration** - Agent works while you're in meetings
- **Feedback loop closed** - Agent can iterate on review comments
- **No context switching** - Agent maintains session state
- **Learning opportunity** - Agent sees what reviewers care about

<!-- pause -->

**Company benefits:**
- Agents improve through review feedback
- Human reviewers aren't blocked waiting for agent dev
- Quality standards maintained (same review process)
- Institutional knowledge propagates to agents

<!-- end_slide -->

Guardrail #5: Nix for Turnkey Setup
===

**All this tooling is useless if onboarding takes 2 hours.**

<!-- pause -->

**Traditional setup hell:**
1. Install agent X (which version?)
2. Configure MCP Y (where's the docs?)
3. Set up auth Z (which env var?)
4. Install tool A, B, C... (dependency hell)
5. Hope it works (narrator: it doesn't)

<!-- pause -->

**With Nix:**
```bash
nix develop github:cbarber/llm-tools#opencode
# Everything just works
```

<!-- end_slide -->

Nix: What You Get
===

**One command provisions:**

- ✅ Agent (OpenCode/Claude Code)
- ✅ Sandbox (bubblewrap configured)
- ✅ Tools (spr, forge, temper, beads)
- ✅ MCP servers (cclsp, others)
- ✅ Auth (API keys sourced)
- ✅ Workflow injection (hooks configured)

<!-- pause -->

**Everything is:**
- Version-pinned (flake.lock)
- Reproducible (same on every machine)
- Isolated (won't break other projects)
- Centrally managed (update once, everyone gets it)

<!-- end_slide -->

Nix: The Honest Tradeoff
===

**Nix has a learning curve.**

<!-- pause -->

**Things that are hard:**
- Understanding flakes
- Debugging Nix errors (cryptic)
- Writing custom packages
- Platform differences (Linux vs macOS)

<!-- pause -->

**But:**
- One-time cost for long-term reproducibility
- Team standardizes on same environment
- Security updates propagate automatically
- Onboarding time: 2 minutes vs 2 hours

<!-- pause -->

**Company benefits:**
- Central configuration management
- Version pinning (prevents "works on my machine")
- Security updates in one place
- Audit trail (what changed when)

<!-- end_slide -->

# Part 4: The Path Forward

<!-- end_slide -->

Current State: Anecdotal Evidence
===

**What I know:**

- Dogfooding for 3 months
- Subjectively significant improvements
- Zero security incidents with sandbox
- Better commit quality with workflow injection
- Faster reviews with SPR

<!-- pause -->

**What I don't know:**

- How much better? (quantitative)
- Which guardrail has most impact?
- Are there interaction effects?
- What's the statistical significance?

<!-- pause -->

**This is honest engineering:**

"This works for me. Let's validate it properly."

<!-- end_slide -->

The Return to Scientific Rigor
===

**The opportunity:**

Full agent sessions = controlled experiments

<!-- pause -->

**What we can measure:**
- Atomic commit rate (before/after each guardrail)
- Commits per PR (before/after)
- Time to complete task
- Security incidents (before/after sandbox)
- Review cycle time

<!-- pause -->

**What we can test:**
- Does workflow injection improve adherence?
- Does guideline ordering matter?
- Is "think step by step" actually helpful?
- Which injection timing is optimal?

<!-- pause -->

**No more cargo culting.**

<!-- end_slide -->

Experimental Methodology
===

**Design: A/B testing with controlled tasks**

1. Select representative tasks from beads (N=20)
2. Run each task twice:
   - Control: Guardrail disabled
   - Treatment: Guardrail enabled
3. Measure outcomes objectively
4. Calculate effect size and significance

<!-- pause -->

**Example: Testing workflow injection**

- Control (N=10): Same AGENTS.md, injection disabled
- Treatment (N=10): Same AGENTS.md, injection enabled
- Measure: % atomic commits, commits per PR
- Hypothesis: Treatment > Control by ≥50%

<!-- pause -->

**Status: Infrastructure ready, experiments planned**

<!-- end_slide -->

The Infrastructure Is Ready
===

**What's already built:**

- ✅ Sandbox (can toggle on/off)
- ✅ Workflow injection (can enable/disable per event)
- ✅ Beads (task tracking with git backing)
- ✅ Metrics collection (git log analysis)
- ✅ Reproducible environment (Nix)

<!-- pause -->

**What's needed:**

- Design experiment protocol
- Select representative tasks
- Run controlled sessions
- Analyze results
- Iterate based on findings

<!-- pause -->

**Timeline: Experiments in progress**

<!-- end_slide -->

The Vision: Evidence-Based AI Engineering
===

**Imagine being able to test:**

- "Does adding '## Context' heading improve task completion?"
- "Does re-injecting guidelines every 10K tokens help?"
- "Is JSON output format better than markdown for tool calls?"
- "Does explicitly saying 'be concise' reduce response length?"

<!-- pause -->

**We can answer these questions.**

**With data. With significance tests. With reproducibility.**

<!-- pause -->

**This is what engineering rigor looks like:**

Not cargo culting best practices.

Testing hypotheses. Measuring outcomes. Iterating.

<!-- end_slide -->

Invitation to Collaborate
===

**This is early days.**

**I'm one data point.**

<!-- pause -->

**I need your help:**

- Design better experiments
- Challenge my assumptions
- Point out what I'm missing
- Help analyze results
- Contribute your own observations

<!-- pause -->

**Open questions I don't have answers for:**

1. Is workflow injection really better than skills? (Need to test)
2. What's the optimal injection timing? (Every edit? Every N edits?)
3. Do the guardrails have interaction effects? (Maybe they amplify each other)
4. What metrics matter most? (Commit quality? Time to complete? Developer satisfaction?)

<!-- pause -->

**Let's figure this out together.**

<!-- end_slide -->

# Discussion

<!-- end_slide -->

Pressure Test the Architecture
===

**I want your skepticism.**

<!-- pause -->

**Questions I expect:**

- "How do you know it's not placebo effect?"
- "Why not just write better prompts?"
- "Isn't this over-engineered?"
- "What about Cursor/Copilot?"
- "Why sandbox instead of better confirmation UX?"

<!-- pause -->

**Questions I hope you ask:**

- "What am I missing?"
- "What smells wrong?"
- "What would change your mind?"
- "How can we test this properly?"

<!-- pause -->

**Open floor for discussion.**

<!-- end_slide -->

Thank You
===

**Questions? Challenges? Ideas?**

<!-- pause -->

**Resources:**

- Repo: `github.com/cbarber/llm-tools`
- Try it: `nix develop github:cbarber/llm-tools#opencode`
- Contribute: Issues, PRs, experiments welcome

<!-- pause -->

**Let's build reliable AI workflows together.**

<!-- end_slide -->
