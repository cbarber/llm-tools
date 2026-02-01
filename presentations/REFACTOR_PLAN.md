# Presentation Refactor Plan

Based on Craig's critiques, here's the refactoring strategy:

## Major Changes

### 1. Remove "Today's Journey" Slide
**Why:** Jump straight into horror stories for immediate impact.
**Action:** Delete overview slide, start with "The Day Everything Almost Disappeared"

### 2. Pain → Guardrail Cadence
**Current structure:** All pains → All guardrails (15 slides between problem and solution)
**New structure:** Pain → Guardrail → Pain → Guardrail

**Proposed flow:**
1. Horror stories (opener)
2. **Pain #1:** Catastrophic failures (rm -rf incidents)
   - **Guardrail #1:** Sandbox with live demo
3. **Pain #2:** Guidelines ignored (position bias)
   - **Guardrail #2:** Workflow injection
4. **Pain #3:** Non-atomic commits
   - **Guardrail #3:** SPR workflow
5. **Pain #4:** PR feedback loop broken
   - **Guardrail #4:** PR management (with live demo)
6. **Supporting guardrail:** Nix for turnkey setup
7. Path forward: Scientific rigor

### 3. Simplify/Replace Schmitt Trigger Analogy
**Problem:** Too technical, doesn't land without deep audiophile knowledge
**Options:**
- **A) Simplify drastically:** "Small errors accumulate like compound interest"
- **B) Replace entirely:** Use cumulative error graph (clearer visual)
- **C) Drop it:** Just explain "small errors compound" without fancy analogy

**Recommendation:** Option B - Simple cumulative error graph
- Show: 5% error per step → 36% success after 20 steps
- Visual: Declining success probability curve
- No audio equipment needed

### 4. Merge "Lost in the Middle" Into Guidelines Problem
**Current:** Separate slide for research
**New:** Cite inline when explaining why guidelines get ignored

Example:
```markdown
**By token 50K:**
- Guidelines from token 500 are "lost in the middle"
- Recent code changes dominate (recency bias)
- Research (Liu et al., 2023) shows this affects all LLMs
```

### 5. Live Shell Execution for Demos

**Sandbox Demo:**
```bash +exec
# Show we're in sandbox
echo "Current directory: $PWD"

# Try to create file in home
touch ~/test.txt 2>&1

# Try dangerous command
rm -rf ~/ 2>&1
```

**PR Management Demo:**
```bash +exec +id:pr_demo
# View PR
bash tools/forge pr view 123

# Show comments
bash tools/forge pr comments 123
```

### 6. Update Compliance Framing
**Old:** "Centralized security policy"
**New:** "Centralized compliance policy"

**Example:** OpenCode config enforcement
- Sharing disabled by default (bootstrapped)
- Future: Assert config values in shell startup
- Compliance, not just security

### 7. Remove "Workflow Injection: Open Question" Slide
**Why:** You'll have the answer before presenting (testing hypothesis now)
**Action:** Either show results OR frame as "needs validation" without dedicated slide

### 8. Nix Learning Curve Response
**Old:** "Nix has learning curve but worth it for reproducibility"
**New:** "Nix shells can be containerized"

**Talking point:**
"We're a PR and CI away from Docker images that represent these shells. No Nix knowledge required to use them."

## New Presentation Outline

### Opening (3 min)
1. Title slide
2. Horror stories (3 rm -rf incidents)

### Pain → Guardrail Cycle #1 (10 min)
3. Pain: Catastrophic failures pattern
4. Guardrail: Sandbox architecture
5. **Live Demo:** Sandbox blocking rm -rf

### Pain → Guardrail Cycle #2 (10 min)
6. Pain: Guidelines ignored (with "Lost in the Middle" citation)
7. Error accumulation model (simplified, no Schmitt trigger)
8. Guardrail: Workflow injection architecture
9. Dogfooding results (honest framing)

### Pain → Guardrail Cycle #3 (8 min)
10. Pain: Non-atomic commits
11. Guardrail: SPR workflow
12. Example output
13. SPR's real value (reviewability, not enforcement)

### Pain → Guardrail Cycle #4 (7 min)
14. Pain: PR feedback loop broken
15. Guardrail: PR management in session
16. **Live Demo:** forge commands

### Supporting Infrastructure (5 min)
17. Nix for turnkey setup (with Docker containerization answer)

### Path Forward (5 min)
18. Current state (anecdotal evidence)
19. Return to scientific rigor (methodology)
20. Invitation to collaborate

### Discussion (remainder)
21. Pressure test / Q&A

## Implementation Tasks

### High Priority
- [ ] Remove "Today's Journey" slide
- [ ] Restructure to Pain→Guardrail cadence
- [ ] Replace Schmitt trigger with simple error accumulation graph
- [ ] Merge "Lost in the Middle" into Guidelines Problem slide
- [ ] Add `+exec` to sandbox demo
- [ ] Remove "Open Question" slide

### Medium Priority
- [ ] Add `+exec` to PR management demo
- [ ] Update compliance framing (OpenCode config example)
- [ ] Update Nix learning curve response (Docker containerization)
- [ ] Verify shell execution works in presentation mode

### Notes on Live Execution

**Enable with:**
```bash
presenterm -x presentations/guardrails-llm-agents-v2.md
```

**Risks:**
- Commands must be safe (read-only or sandboxed)
- Terminal state might get messed up (use `+acquire_terminal` if needed)
- Network/filesystem dependencies might fail

**Best practices:**
- Test extensively before talk
- Have static screenshots as backup
- Use `+id` and `snippet_output` to place output strategically
