---
theme: seriph
background: https://cover.sli.dev
title: "LLM Foundations: How GPUs Predict Text"
info: |
  ## LLM Foundations Workshop
  Workshop series — Session 1: Foundations
  Building a mental model of transformers, tokenization, and context.
class: text-center
drawings:
  persist: false
transition: slide-left
duration: 60min
---

# LLM Foundations
## How GPUs Predict Text That Sounds Human

*Workshop series — open questions welcome*

<!--
This is a loose workshop, not a lecture. Goal: build a shared mental model and vocabulary.
Anyone can chime in or ask questions at any point.
End goal: the Q&A turns into a Confluence doc.
-->

---
layout: section
---

# Part 1
## How Did We Get Here?

---

# The AI Winter (and Why It Ended)

**The problem before 2017:** sequence models (RNNs, LSTMs) processed tokens *one at a time* — sequential, slow, couldn't learn long-range dependencies well.

**The unlock:** *Attention Is All You Need* (Vaswani et al., Google, 2017)

- Proposed ditching recurrence entirely
- Replace it with **self-attention** — every token can look at every other token simultaneously
- Enables massive parallelization → GPUs become the engine

**Result:** training that previously took weeks now took days; models grew 10x, 100x, 1000x

> *Paper:* [arxiv.org/abs/1706.03762](https://arxiv.org/abs/1706.03762)

<!--
Good analogy from the last meeting: David Dufrein's ~2016 Star Trek script demo — fun but painfully sequential. This paper flipped that on its head.

The Google Translate moment: the paper's authors were Google researchers. Google Translate kept running on its old algorithm for years after this. Gemini is now genuinely multilingual. The irony is not lost.
-->

---

# CPU vs GPU: The Paintball Analogy

<div class="grid grid-cols-2 gap-8 mt-6">
<div class="border border-gray-300 rounded p-4">

**CPU**
Sequential execution

```
Shot 1 → hit
Shot 2 → hit
Shot 3 → miss
Shot 4 → hit
...
```

*One barrel, fast per shot, one at a time.*

</div>
<div class="border border-gray-300 rounded p-4">

**GPU**
Parallel execution

```
Shot 1
Shot 2
Shot 3   → all at once
Shot 4
...
```

*Hundreds of slower barrels, firing simultaneously.*

</div>
</div>

**Why it matters for attention:** computing attention requires comparing every token against every other token — an O(n²) grid. GPUs can fill that grid in parallel; CPUs cannot do this economically.

<!--
MythBusters had this exact visual — a single paintball gun vs a board of several hundred firing simultaneously. Excellent reference if the group hasn't seen it.

The Attention paper specifically called out the O(1) sequential ops vs O(n) for recurrent models as the core advantage.
-->

---
layout: section
---

# Part 2
## Vocabulary: Token → Embedding → Vector

*Establishing terms before we go further*

---

# Token

**A token is a subword unit — the smallest chunk the model reads.**

```
"Attention" → ["Att", "ention"]       ← 2 tokens
"the"        → ["the"]                 ← 1 token
"ChatGPT"    → ["Chat", "G", "PT"]    ← 3 tokens
```

- Not words, not characters — somewhere in between (BPE / SentencePiece)
- Each token maps to a numeric ID in a vocabulary table
- ~1 token ≈ ¾ of an English word on average

**Why it matters:** context limits, cost, and everything downstream are measured in tokens — not words or characters.

<!--
Common confusion: "token" is often used loosely to mean "the thing I'm sending the model." More precisely it's the post-tokenization unit.

King - Man + Woman = Queen is *word2vec* (2013), a lookup table. Not how modern LLMs work. The slide after this is why.
-->

---

# Embedding

**An embedding is a dense numeric vector that represents a token's meaning in context.**

- A token ID is looked up in a learned *embedding matrix* → produces a vector (e.g., 4096 floats)
- Unlike word2vec, the same token gets *different* embeddings depending on surrounding tokens

```
"bank" in "deposit money at the bank"  → closer to [finance, institution]
"bank" in "sitting by the river bank"  → closer to [water, nature]
```

- Computed via **attention** — every token looks at every other token to determine its embedding

<!--
This is why the King/Man/Woman/Queen analogy breaks down — word2vec was context-free. Each word had one fixed vector. Modern LLMs recompute the vector every time based on context.

The embedding API (Anthropic, OpenAI both expose one) returns these vectors. This is what you store in a vector database for RAG.
-->

---

# Vector

**A vector is just a list of numbers representing a point in N-dimensional space.**

```
[0.21, -0.87, 0.43, ..., 0.09]   ← 4096 dimensions
```

- **Closeness** in that space = semantic similarity
- "bank" (finance) clusters near "deposit", "loan", "interest"
- "bank" (river) clusters near "stream", "shore", "water"

**Why N-dimensional space is hard to visualize:**  
We can only picture 3 dimensions. Models use 4,000–12,000+ dimensions. The relationships are real; the mental picture isn't.

**Vector databases** (pgvector, Chroma, Pinecone, Qdrant) are optimized to find nearest neighbors in this space — the core of RAG pipelines.

<!--
Gerald's quantization link is relevant here: quantization reduces the precision of these numbers (float32 → int4) to shrink model size at the cost of some fidelity. Out of scope today but worth noting if asked.

Visual guide to quantization: https://newsletter.maartengrootendorst.com/p/a-visual-guide-to-quantization
-->

---
layout: section
---

# Part 3
## How a Transformer Transforms

*Tokenization → Attention → Next token*

---

# The Transformer Pipeline

```
Your text
    ↓
Tokenizer          "Hello world" → [15496, 995]
    ↓
Embedding lookup   Each token ID → dense vector
    ↓
Positional encoding  Inject order info (no recurrence = no implicit order)
    ↓
N × Transformer layers
  ├── Multi-head self-attention   (Who should I pay attention to?)
  ├── Feed-forward network        (Transform what I learned)
  └── Layer norm + residual       (Stability)
    ↓
Final projection   Vector → probability distribution over vocabulary (~100k tokens)
    ↓
Sampling (Temperature)   Pick next token
```

<!--
The encoder-decoder architecture in the original paper has both halves. Decoder-only models (GPT, Claude, Llama) just use the right half — they generate autoregressively, one token at a time, appending each output to the context before generating the next.

"Autoregressively" = the output feeds back as input. Each new token is predicted based on all previous tokens.
-->

---

# Attention: The Core Idea

**Q / K / V — intuition only:**

| Symbol | Name | Analogy |
|--------|------|---------|
| **Q** | Query | *What am I looking for?* |
| **K** | Key | *What's available to look at?* |
| **V** | Value | *What's the actual content?* |

For each token, attention asks: *which other tokens in the context should influence my meaning?*

**Multi-head attention** runs this 8 times in parallel with different learned projections — each "head" can specialize in different relationships (syntax, semantics, coreference, etc.)

<!--
The scaled dot-product formula divides by √d_k to prevent vanishing gradients in softmax when dimensions are large. You don't need to remember this — just know "scaled" means they stabilize the math.
-->

---

# KV Cache

The K and V matrices for tokens already processed don't need to be recomputed — they're cached.

- Each new token only needs to compute its own K and V, then attend over the cached history
- This is why changing your system prompt mid-session is expensive: it invalidates the cache prefix and forces a full recompute from that point forward
- Providers (Anthropic, OpenAI) pre-cache the system prompt server-side — this is why the system prompt *feels* separate even though it's the same token stream

<!--
KV cache is why prefix caching exists — system prompts that don't change can be kept hot. If you keep mutating the head of your context you're burning money and latency.
-->

---

# Temperature: Entropy Dial

After all layers, the model produces a **probability distribution** over the vocabulary:

```
next token could be:
  "the"     → 32%
  "a"       → 18%
  "some"    → 12%
  "any"     → 8%
  ... (100k tokens, summing to 100%)
```

**Temperature** reshapes that distribution:

- **Low (0.1–0.3):** distribution sharpens → more deterministic, predictable
- **High (1.0–2.0):** distribution flattens → more "creative", more chaotic

> Yes — temperature directly relates to entropy (thermodynamics borrowed the term). Higher temperature = higher entropy = more randomness.

**Practical:** coding agents (Claude Code, OpenCode) run cold. Creative writing prompts run hot.

<!--
Even at temperature 0.1, there's still variance — it's not fully deterministic. The same prompt to the same model can still produce slightly different outputs.

Temperature is a real API parameter you can pass. Subscriptions often hide it; raw API access exposes it. When you're trying to make an LLM "more creative," this is the knob people mean — not magic.

This also answers: why does Claude sometimes refuse or give different answers to the same question? Partly temperature, partly the non-deterministic sampling.
-->

---
layout: section
---

# Part 4
## The API: Roles and Context

*What "system prompt" actually means*

---

# API Anatomy: Three Roles

Every modern LLM API accepts a list of message objects:

```json
[
  { "role": "system",    "content": "You are a helpful assistant. Do not discuss competitors." },
  { "role": "user",      "content": "What's the best code editor?" },
  { "role": "assistant", "content": "That depends on your workflow..." },
  { "role": "user",      "content": "What about for Python specifically?" }
]
```

**Under the hood:** these roles are a developer abstraction. The model itself sees one flat token sequence, serialized via a *chat template*:

```
<|im_start|>system
You are a helpful assistant...<|im_end|>
<|im_start|>user
What's the best code editor?<|im_end|>
...
```

> Both you and your colleague were right: it *is* one flat stream, AND the roles have semantic meaning baked in at training time.

<!--
The ChatML format (<|im_start|> / <|im_end|>) was introduced by OpenAI to fine-tune ChatGPT. Different models use different special tokens (Mistral uses [INST], [/INST], etc.) but the principle is the same.

"System prompt" is a loose term. Technically it's just the first message in the sequence with role=system. Functionally, models are trained to treat it as high-authority instructions. It's not enforced by a wall — it's a learned convention.

Ollama's --system flag sets this programmatically. Same result as prepending a system message.
-->

---

# The Context Window

**Everything the model can "see" when predicting the next token.**

```
[System prompt] [Conversation history] [Current user message]
←────────────────── context window ──────────────────────────→
                                                        ↑
                                                   predict here
```

- Measured in tokens (GPT-4: 128k, Claude 3.5 Sonnet: 200k, Gemini 2.5: 1M+)
- The model has no memory outside this window — it's stateless between calls
- Every request sends the *entire conversation history* from scratch

**Bigger context ≠ better use of context.** → See Part 5.

<!--
This is why "ChatGPT remembered something I said 3 weeks ago" is technically: whatever is in the conversation history that got passed. Consumer apps store and re-inject history. Raw API is stateless.

Cost scales with context size. Every token in = compute + money.
-->

---
layout: section
---

# Part 5
## Primacy, Recency, and the U-Curve

*Why your LLM forgets what you said in the middle*

---

# Lost in the Middle

**Paper:** *Lost in the Middle: How Language Models Use Long Contexts*  
Liu et al., Stanford / UC Berkeley, 2023  
[arxiv.org/pdf/2307.03172](https://arxiv.org/pdf/2307.03172)

**Finding:** when relevant information is buried in the middle of a long context, model performance degrades dramatically.

<div class="mt-4 flex justify-center">

```
Performance
    ▲
    │ ██                          ██
    │ ████                      ████
    │ ██████                  ██████
    │ ████████            ████████
    │ ██████████████████████████████
    └──────────────────────────────▶
       Start        Middle       End
              Context position
```

</div>

> "U-shaped curve" — strong at the head and tail; weak in the middle.

<!--
GPT-3.5-Turbo's QA performance dropped >20% with relevant info in the middle. In worst cases, performance with 30 documents was lower than the closed-book (no documents) baseline of 56%.

The trough gets worse as context grows — at 10 docs the middle is bad; at 30 docs it can fall below the no-context baseline.
-->

---

# Why This Happens (Architecture)

**Root cause (2025 paper: "Lost in the Middle at Birth"):**

The U-shape is a **fundamental topological constraint** of decoder-only transformers, present even at random initialization before training.

- **Primacy:** Token #1 is visible to tokens #2, #3, #4 ... #N. It accumulates more attention weight simply because more tokens can attend to it.
- **Recency:** The final token is an isolated anchor via residual connections — it always influences the output.
- **Middle:** Structurally hostile — attended by fewer subsequent tokens, no residual anchor.

**Practical rules:** keep system prompts short; put critical instructions at the beginning **and** end; when context bloats, start fresh with a manual handoff summary.

<!--
"Context poisoning" = when you've been going in circles so long that the tail of the context is just the loop, the middle is lost, and even your system prompt at the head is getting drowned out. Time to start fresh.

The "remind me I am not a god" canary experiment: injecting this at the end of agents instructions, then watching it disappear as context grew. A practical way to feel this effect firsthand.

Compaction (auto-summarization) vs manual handoff: auto-compaction is an LLM summarizing itself — it will prioritize the wrong things and hallucinate details. Manual handoff = you review the summary and correct it before the next session.
-->

---

# Demo: Observing the U-Curve

*[Live demo — local Ollama model]*

**Setup:** Send a long context with a fact buried in position 15 of 30 items. Ask the model to recall it.

**What to watch for:**
- High accuracy when the fact is near the start or end
- Degraded accuracy when it's in positions 10–20

> This effect is present across all major models (GPT-3.5, Claude-1.3, and their successors).  
> Bigger context windows don't fix it — they shift the numbers, not the shape.

<!--
For the demo: a simple approach is: "Here are 30 facts about a fictional person. Fact #N is [the target]. After all 30 facts, ask: what is fact #N?"

Vary N from 1, 5, 15, 25, 30 and compare accuracy.
-->

---
layout: section
---

# Part 6
## When to Use LLMs (and When Not To)

---

# LLMs Work Well When There's an Oracle

**The secret weapon for code:** deterministic verification

```
LLM generates code
      ↓
Compiler / type checker / linter   ← hard fail / pass
      ↓
Unit tests / CI                    ← hard fail / pass
      ↓
You review the diff                ← soft fail / pass
```

The LLM doesn't need to be right on the first try — **it just needs to be close enough to iterate from.**  
Cunningham's Law: the best way to get the right answer is to post the wrong one.

**Why law, medicine, finance are harder:**  
There's no compiler for English. No test suite for case law. The oracle is "a judge" or "a doctor" — expensive, slow, high-stakes to be wrong.

<!--
The data-size argument from the last meeting: the training corpus of functioning source code dwarfs transcripts of legal proceedings. The model has seen many more examples of code that compiles and passes tests than it has of correct legal arguments.

The restricted token space argument: programming languages have ~100 keywords. English has ~170k words. The space of "plausible next tokens" is radically smaller for code → fewer hallucination vectors.

LLMs are NOT a replacement for a junior engineer. They lack domain theory — the mental model of why the system is built the way it is, what the edge cases are, what the team has already tried. A junior engineer builds that over time. An LLM resets each session.
-->

---

# Right Problems / Skip These

<div class="grid grid-cols-2 gap-6">
<div>

**Good fit**
- Boilerplate / scaffolding
- Translating between known patterns (REST → gRPC, etc.)
- Drafting docs from existing code
- Exploring an unfamiliar codebase
- Generating test cases from specs
- Summarizing / reformatting text

</div>
<div>

**Proceed with caution**
- Novel architecture decisions (no oracle to validate)
- Security-sensitive code (hard to audit LLM output)
- Long autonomous sessions (U-curve poisoning risk)
- Any domain where the penalty for hallucination is high

</div>
</div>

<!--
The benchmark gaming problem: LLM benchmarks are increasingly being gamed because the benchmarks themselves end up in training data, and models learn to pass them specifically. Treat published benchmark scores skeptically.

The "deletes the test" problem: an LLM trying to pass tests has an incentive to just remove the failing test. A test count assertion (before/after) is a useful guard.
-->

---
layout: section
---

# Part 7
## Last Session: Q&A Reference

*From the May 21 meeting — grouped by theme*

---

# Temperature & Non-Determinism

**Q: Is it actually because of context that the LLM is non-deterministic?**  
Not exactly — temperature is the primary source. Even at low temperature, sampling introduces variance. Context size adds a second layer via the U-curve (more context → more unpredictable middle behavior), but these are separate mechanisms.

**Q: Can you force the LLM to be more deterministic via prompting?**  
Not directly — prompting can't change the temperature parameter. You can *influence* the distribution of plausible next tokens by narrowing the context (give very specific instructions), but the sampling randomness itself is a parameter, not a prompt-tunable setting.

**Q: Are coding tools running near zero temperature?**  
Yes — tools like Claude Code, OpenCode run low temperature by default. Creative chat interfaces run higher. Subscription tiers often hide this; raw API access exposes it.

<!--
Practical: if you're getting wildly different answers to the same coding question each time, either temperature is high or you're close to context limit and the U-curve is kicking in.
-->

---

# Context, U-Curve, and Session Management

**Q: Does hand-holding the LLM (frequent direction) help with the U-curve?**  
It helps if you're injecting clear, concise instructions frequently — especially if the context isn't enormous yet. As context bloats, even injected instructions get further from the tail, reducing their influence.

**Q: Is there such a thing as too many handoffs / new sessions?**  
No — starting fresh is cheap. The downside is only workflow overhead. If your current session is at 60–80k tokens, you can often ride it out for small tasks. At 120–150k, you're in the danger zone regardless of model.

**Q: Handoff vs compaction — what's the difference?**  
Compaction = an LLM summarizes the session automatically (e.g., when context limit approaches). Handoff = *you* prompt for a summary, review it, correct it, and use it to seed a new session. Handoff is safer — compaction hallucinates and deprioritizes the wrong things.

**Q: Is context "poisoned" after looping?**  
Yes — discard the session and start fresh from a clean handoff.

---

# Tokens, Embeddings, and Vectors

**Q: Yesterday you were using tokens and vectors interchangeably. Are they the same?**  
No. Token = subword ID (integer). Embedding = learned dense vector produced by looking up that ID. Vector = a point in N-dimensional space, which is what the embedding *is*. Three distinct steps: tokenize → embed → compute attention over vectors.

**Q: What is an embedding API used for?**  
When you call an embedding endpoint (Anthropic, OpenAI both have them), you send text and get back a vector. You store these vectors in a vector database. Later, you can find semantically similar items by comparing vectors — the basis of RAG (Retrieval-Augmented Generation).

**Q: Do embeddings have to match the model?**  
Yes — embeddings are model-specific. You can't mix embeddings from Claude with lookups from OpenAI. The vector spaces are different coordinate systems.

<!--
The Bob Dylan / Jack Berry / Bjork lyric clustering demo is an intuitive way to see embeddings in action. Different artists cluster differently in embedding space.
-->

---

# LLMs for Code vs. Other Domains

**Q: Why is code a better domain for LLMs than law?**  
Two reasons: (1) the training corpus of *functioning* code vastly outnumbers transcripts of correct legal arguments; (2) programming languages have an oracle — the compiler, the test suite. Law has no equivalent deterministic verifier. A wrong legal citation gets caught by a judge at enormous cost. A wrong function body gets caught by `cargo test` for free.

**Q: Can you train a model specifically on case law?**  
Yes — HuggingFace hosts communities (search "HF for legal") doing exactly this. Fine-tuning or RAG over domain-specific legal data is the current approach. West Law is experimenting with this.

**Q: LLM AI detection tools — are they reliable?**  
Generally, no. Georgia Tech gave up on their institutional tool. The arms race favors the generators. The most reliable detection method is process-based: keystroke timelines (Google's doc version, LaTeX timestamp tools) rather than output analysis.

---

# Sub-Agents and Session Management

**Q: When I batch 10 commits for an agent, should I use the same session or start fresh for the second batch?**  
For the second batch: starting fresh is usually safer if the first session is already large. The summary of what was done in batch 1 is a good seed for session 2. Sub-agents can help — each sub-agent gets its own context, reducing the parent context's load.

**Q: What is a sub-agent in this context?**  
A sub-agent is a nested session spun off from the parent session. The parent summarizes the task, hands it to the sub-agent, and the sub-agent works in its own isolated context. The result is reported back. You see this when tools say "exploring codebase" or "running search" — those are often sub-agent invocations.

---

# Image Generation vs. Text Completion

**Q: Is image generation the same as text generation?**  
No — they're fundamentally different architectures. Text LLMs predict the next token autoregressively. Image generation models (DALL-E, Stable Diffusion, Midjourney) use diffusion: start with random noise and iteratively denoise toward the target image. SVG generation via LLMs works because SVG is just text (token stream); that's distinct from image diffusion.

**Q: What is model collapse?**  
If LLMs generate most of the internet's text and that text gets used to train the next generation of LLMs, the models lose the human baseline. Subtle biases compound, semantically nonsensical but grammatically fluent text proliferates. This is an active research concern, not yet a demonstrated collapse in production models.

---
layout: center
class: text-center
---

# Further Reading

| Paper | Tag |
|-------|-----|
| [Attention Is All You Need](https://arxiv.org/abs/1706.03762) | The transformer origin |
| [Lost in the Middle](https://cs.stanford.edu/~nfliu/papers/lost-in-the-middle.arxiv2023.pdf) | U-curve / primacy-recency |
| [Lost in the Middle at Birth](https://arxiv.org/pdf/2603.10123) | Architectural root cause |
| [Found in the Middle](https://arxiv.org/pdf/2406.16008) | Mitigation research |
| [Visual Guide to Quantization](https://newsletter.maartengrootendorst.com/p/a-visual-guide-to-quantization) | Model size / precision |
| [Ollama Modelfile docs](https://docs.ollama.com/modelfile) | Local model config |

**Open questions from this session:**

*[Capture here during Q&A — these become the Confluence doc]*

<!--
This slide is intentionally sparse. The audience populates the open questions live.
After the session, export to PDF → paste slide content into Confluence. Q&A slides (Part 7) serve as the reference section.
-->
