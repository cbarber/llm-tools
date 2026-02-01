# Research Summary: Context Window Position Bias

## The Core Research

**Paper:** "Lost in the Middle: How Language Models Use Long Contexts"  
**Authors:** Nelson F. Liu, Kevin Lin, John Hewitt, Ashwin Paranjape, Michele Bevilacqua, Fabio Petroni, Percy Liang  
**Published:** Transactions of the Association for Computational Linguistics (TACL), 2023  
**arXiv:** https://arxiv.org/abs/2307.03172

## Key Findings

### Position Bias in Long Contexts

LLMs do NOT use information uniformly across their context window. Performance depends heavily on WHERE information appears:

1. **High Performance Positions:**
   - **Beginning of context** - Information here is readily accessible
   - **End of context** - Recent information (recency bias)

2. **Low Performance Position:**
   - **Middle of context** - Information here is often "lost"
   - Significant performance degradation occurs

### Impact on Multi-Document QA

The research tested models on tasks requiring them to identify relevant information in long contexts:
- Multi-document question answering
- Key-value retrieval

**Result:** Performance degrades significantly when relevant information is in the middle of long input contexts, even for models explicitly designed for long contexts.

### Why This Matters for AGENTS.md

**Your original intuition was correct, but the mechanism is different:**

| Your Understanding | Actual Research |
|-------------------|-----------------|
| "Attention decay" | Position bias / "Lost in the middle" |
| "Recent context dominates" | ✅ Correct (recency bias) |
| "Guidelines at token 0 have ~0% weight" | ❌ Not quite - they have high weight initially, but get "buried" as they move toward the middle |

**What actually happens:**

```
Token 0-2K:     AGENTS.md (HIGH INFLUENCE - at beginning)
Token 2K-40K:   Intervening context (AGENTS.md now in MIDDLE)
Token 40K-50K:  Recent code/decisions (HIGH INFLUENCE - at end)
```

By the time the agent is at token 50K making decisions:
- Your guidelines from token 0-2K are now "lost in the middle"
- Recent context at token 40K+ has high influence (recency bias)
- Result: Guidelines are effectively ignored

## Anthropic's Related Research: Many-Shot Jailbreaking

**Paper:** "Many-shot jailbreaking" (Anthropic, April 2024)  
**URL:** https://www.anthropic.com/research/many-shot-jailbreaking

**Key insight for your presentation:**

This research shows that longer context windows create NEW vulnerabilities:
- Technique works by including many examples (up to 256) in a single prompt
- Effectiveness scales with context window size
- Demonstrates that "positive improvements" (longer contexts) can have unforeseen consequences

**Relevance to your talk:**

This supports your point about guardrails being necessary. Even beneficial features (long contexts) can create problems that need structural solutions (not just better prompts).

## Implications for Workflow Boundary Injection

### Why Re-Injection Works

Based on the "Lost in the Middle" research, workflow boundary injection is effective because:

1. **Injection happens at the END of context** (high influence position)
2. **Fresh context appears RIGHT WHEN needed** (at decision point)
3. **Avoids the middle-context degradation** (doesn't rely on old context)

### The Mechanism

```
WITHOUT INJECTION:
Token 0-2K:    Guidelines (start - initially high influence)
Token 2K-40K:  Work context (guidelines now in middle - LOW influence)
Token 40K-50K: Decision time (guidelines are "lost")
Result: Agent ignores guidelines ❌

WITH INJECTION:
Token 0-2K:    Guidelines (start)
Token 2K-48K:  Work context  
Token 48K:     file.edited event → RE-INJECT guidelines
Token 48K-50K: Guidelines (end - HIGH influence) + decision
Result: Agent follows guidelines ✅
```

## For Your Presentation

### Accurate Framing

**DON'T say:**
- "Attention decays exponentially"
- "Guidelines have 0% weight by token 50K"
- "This is how attention mechanisms work"

**DO say:**
- "Research shows LLMs struggle with information in the middle of long contexts"
- "This is called the 'lost in the middle' phenomenon (Liu et al., 2023)"
- "Information at the beginning or end has highest influence"
- "My guidelines start at the beginning but get buried as context grows"

### Citations You Can Use

1. **Primary citation:**
   - Liu et al., "Lost in the Middle: How Language Models Use Long Contexts", TACL 2023

2. **Supporting citation:**
   - Anthropic, "Many-shot jailbreaking", April 2024
   - Use this to show: longer contexts create new challenges that need guardrails

### The Narrative

**Opening:**
"I was frustrated that agents ignored my carefully written guidelines. Then I learned about research on how LLMs use long contexts."

**The insight:**
"Research by Liu et al. (2023) found that LLMs have what they call a 'lost in the middle' problem: information in the middle of long contexts is significantly harder for the model to access and use."

**The connection:**
"My guidelines were at the start - high influence initially. But as the context grows to 50K tokens, those guidelines end up buried in the middle, exactly where the research shows performance degrades."

**The solution:**
"Workflow boundary injection solves this by re-injecting guidelines at the END of context, right when they're needed. The research shows this position has high influence due to recency bias."

## Additional Resources

### More on Position Bias
- The research shows this is NOT specific to any one model architecture
- Affects multiple model families (GPT, Claude, others)
- Gets somewhat better with larger models, but doesn't disappear

### Many-Shot Learning Connection
- The "Lost in the Middle" paper also discusses how in-context learning scales
- Your observation about workflow injection following similar patterns is on point
- Both benign in-context learning AND jailbreaking follow power law scaling

## Questions to Anticipate

**Q: "Isn't this just prompt engineering?"**
A: "No - research shows you can't prompt your way out of position bias. Information in the middle is systematically harder to access. Workflow injection is a STRUCTURAL solution, not a prompt tweak."

**Q: "Does this affect all models?"**
A: "Yes. The 'Lost in the Middle' paper tested multiple model families. It's better in some than others, but the pattern exists across the board."

**Q: "What about models with attention mechanisms designed for long contexts?"**
A: "Even models explicitly designed for long contexts show this degradation. It's an active research area, but current models all exhibit this to some degree."

**Q: "How do you know workflow injection actually helps?"**
A: "That's what I'm working to measure rigorously. The theory predicts it should help (puts guidelines at high-influence position). My anecdotal experience matches that. Next step is A/B testing to quantify the effect."

## Honest Limitations

**What you CAN'T claim:**
- That you fully understand the attention mechanism
- That you've proven workflow injection works (you haven't A/B tested yet)
- Specific percentages or effect sizes (you don't have data)

**What you CAN claim:**
- Research shows position bias exists ("Lost in the Middle")
- Your experience matches what the research predicts
- Workflow injection is theoretically sound (targets high-influence position)
- You're building infrastructure to test it rigorously

## Bottom Line

Your intuition was RIGHT - context position matters. 

The research gives you solid grounding to explain WHY workflow injection should work, even if you don't yet have quantitative proof that it DOES work.

Frame it honestly: "Theory predicts this should help, my experience suggests it does, next step is rigorous measurement."
