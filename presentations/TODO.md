# Presentation TODO

## Priority 1: Critical for Credibility

### Document rm -rf Incidents Precisely
- [ ] Git worktree script incident
  - Context: Building script to manage git worktrees
  - Command: `git rm -rf .` buried in script
  - Result: Entire local repo deleted (fortunately pushed)
  - Why dangerous: Deletion hidden in script logic

- [ ] npm debugging incident
  - Context: Debugging npm dependency issues
  - Sequence: npm fails → clean cache → cache fails → suggest `rm -rf ~/`
  - Result: Caught in confirmation prompt
  - Why terrifying: Each step seemed reasonable individually

- [ ] Documentation sync script incident  
  - Context: Writing script for orphan branch sync
  - Suggestion: `rm -rf * .[^.]*` to "clean" directory
  - Your response: "That is the opposite of safe"
  - Agent: "You're absolutely right. I'm an idiot."
  - Why dangerous: Would be copied by others from documentation

### Prepare Honest Evidence Framing
- [ ] Practice saying: "I don't have rigorous data yet, here's why that's next"
- [ ] Draft responses to "where's the data?" questions
- [ ] Show the experimental methodology you're building
- [ ] Emphasize: Infrastructure is ready, experiments in progress

### Clarify Recency Bias (not "attention decay")
- [ ] Frame as: "Recent context dominates" not "attention decays exponentially"
- [ ] Source: YouTube video explaining LLM functioning (can't cite specifically)
- [ ] Key insight: Guidelines at token 0 compete with 50K tokens of recent context
- [ ] Safer claim: Context window recency bias, not attention mechanism specifics

## Priority 2: Strengthens Presentation

### Create Before/After Examples
- [ ] Find god commit from before workflow injection
  - Look in git history from before workflow hooks implemented
  - Something mixing feat + fix + refactor
  
- [ ] Find atomic commits from after workflow injection
  - Recent commits from last month
  - Show clean, single-purpose commits
  
- [ ] Format for slides: side-by-side comparison

### Test Skills Hypothesis
- [ ] Create commit-guidelines skill for Claude
- [ ] Run 3-5 sessions without workflow injection
- [ ] Observe: Does agent call skill? When? How consistently?
- [ ] Document findings for presentation
- [ ] Use to clarify complementary nature (pull vs push)

### Collect Informal Metrics
- [ ] Count atomic commits in last 20 sessions
  - Use: `git log origin/main..HEAD --oneline | wc -l`
  - Manually review each commit message
  - Calculate: % that are truly atomic (single concern)

- [ ] Count security incidents with sandbox
  - Should be zero since enabling sandbox
  - Note date sandbox enabled for timeline

- [ ] Time to merge PRs (rough average)
  - Sample last 10 PRs
  - Calculate: time from PR open to merge
  - Compare to pre-SPR if possible

## Priority 3: Demo Preparation

### Terminal Audio Visualization (Live Demo)
See `presentations/AUDIO_DEMO_RESEARCH.md` for detailed research.

- [ ] Research terminal audio tools (sox, cava, etc.)
- [ ] Test audio input from meeting room computer
- [ ] Create square wave conversion visualization
- [ ] Multiple dry runs in meeting room setup
- [ ] Prepare static fallback (animated GIF or diagram)

**Decision point:** Is this worth the complexity?
- **Pro:** Very visceral demonstration of Schmitt trigger concept
- **Con:** Technical risk, possible distraction from content
- **Alternative:** Pre-recorded visualization or clear static diagram

### Prepare Terminal Demos
- [ ] **Sandbox demo:** Attempt `rm -rf ~/`
  - Record with asciinema as backup
  - Show: `echo $PWD`, `touch ~/test.txt`, `rm -rf ~/`
  - Expected: Permission denied for HOME access

- [ ] **SPR workflow demo:** Real branch with stacked commits
  - Record with asciinema as backup
  - Show: `spr update`, `spr status`, (maybe `spr merge` on test branch)
  - Use existing branch or create demo branch

- [ ] **Forge commands demo:** View PR, comments
  - Record with asciinema as backup
  - Show: `bash tools/forge pr view 123`, `bash tools/forge pr comments 123`
  - Use real PR or create demo PR

**Backup plan:** Have all asciinema recordings ready to play if live demos fail

### Design Minimal Experiment (If Time Permits)
- [ ] Pick 5 simple tasks from beads
  - Tasks should be similar complexity
  - Tasks should naturally involve commits
  - Examples: Add feature, fix bug, refactor function

- [ ] Run with workflow injection OFF (baseline)
  - Disable injection in config
  - Complete all 5 tasks
  - Measure: # commits per task, % atomic commits

- [ ] Run with workflow injection ON (treatment)
  - Enable injection in config
  - Complete same 5 tasks (or similar)
  - Measure: same metrics

- [ ] Calculate difference
  - Even small sample size > no data
  - Be honest about statistical limitations
  - Frame as "preliminary findings"

## Priority 4: Polish

### Create Presenter Notes
- [ ] Timing for each section
  - Part 1 (Problems): 15 min target
  - Part 2 (Insight): 10 min target
  - Part 3 (Guardrails): 30 min target
  - Part 4 (Path Forward): 5 min target
  
- [ ] Key points to emphasize
  - Honesty about anecdotal evidence
  - Engineering rigor as goal
  - Invitation to collaborate

- [ ] Transition phrases between sections
  - "Now that we've seen the problems..."
  - "This insight led to..."
  - "Let me show you how this works in practice..."

### Prepare for Objections
Draft responses to likely questions:

- [ ] **"How do you know it's not placebo?"**
  - "I don't. That's why I'm building measurement infrastructure. Want to help design the experiments?"

- [ ] **"Why not just write better prompts?"**
  - "I tried. Context length vs coverage is a fundamental tradeoff. Injection solves it structurally."

- [ ] **"Isn't this over-engineered?"**
  - "For one-off scripts, yes. For 100+ agent sessions with production consequences, it pays for itself."

- [ ] **"What about Cursor/Copilot/other agents?"**
  - "Sandbox works universally. Workflow injection needs event hooks (OpenCode/Claude Code have them, others TBD)."

- [ ] **"Why sandbox instead of better confirmation UX?"**
  - "Confirmation requires human in loop (blocks automation). Selective confirmation = incomplete coverage (blacklist fails). Sandbox is whitelist (secure by default)."

- [ ] **"Can you prove workflow injection works?"**
  - "Not yet. I have infrastructure to test it. Here's the methodology. Want to collaborate?"

### Test Presentation Flow
- [ ] Run through with `presenterm` once
- [ ] Check slide transitions (<!-- pause --> markers)
- [ ] Verify timing (60 min target with buffer for Q&A)
- [ ] Practice terminal switches (smooth transitions)
- [ ] Test backup recordings (asciinema playback)

## Open Questions to Address

### 1. Workflow Injection vs Claude Skills
**Status:** Need to experiment

**When to test:**
- Before presentation if possible
- Or frame as "planned experiment" in talk

**How to present:**
- If tested: Show results, validate push vs pull distinction
- If not tested: Present hypothesis, invite collaboration

### 2. Live Audio Demo Feasibility
**Status:** Ambitious, high technical risk

**Decision needed:**
- Is the visceral impact worth the risk?
- Can you get reliable audio input in meeting room?
- Do you have time to test thoroughly?

**Recommendation:**
- Start with research (see AUDIO_DEMO_RESEARCH.md)
- Test extensively
- If any doubts: Use static/pre-recorded visualization
- Don't let demo tech overshadow content

### 3. Timeline & Urgency
**Status:** No date set yet

**Questions:**
- How much time before presentation?
- What's minimum viable vs complete?
- Which priority items are must-have vs nice-to-have?

**Recommendation:**
- Focus on Priority 1 items first (credibility)
- Priority 2 strengthens but isn't critical
- Priority 3 demos add polish but have backups
- Priority 4 is time-permitting refinement

## Resources Created

- **Presentation:** `presentations/guardrails-llm-agents.md`
- **TODO List:** `presentations/TODO.md` (this file)
- **Audio Demo Research:** `presentations/AUDIO_DEMO_RESEARCH.md` (to be created)
- **Presenter Notes:** `presentations/PRESENTER_NOTES.md` (to be created)

## Next Actions

1. **Immediate:** Review presentation markdown, iterate on content
2. **This week:** Priority 1 items (incidents, evidence framing)
3. **Before presentation:** Priority 2 + 3 items as time permits
4. **Day before:** Run through with presenterm, test all demos
