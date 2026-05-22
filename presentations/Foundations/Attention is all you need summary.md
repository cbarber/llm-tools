# Attention is all you need summary

## User

Provide a succinct summary of this paper assuming I have some foundational LLM knowledge
https://proceedings.neurips.cc/paper_files/paper/2017/file/3f5ee243547dee91fbd053c1c4a845aa-Paper.pdf

## Claude

"Attention Is All You Need" (Vaswani et al., 2017) — the paper that introduced the Transformer.

**The core problem it solved:** Prior sequence models (RNNs, LSTMs) processed tokens sequentially, which prevented parallelization and made learning long-range dependencies hard. Attention mechanisms existed but were bolted onto RNNs as a supplement.

**The key insight:** Ditch recurrence entirely. Build a model architecture based *solely* on attention — no RNNs, no convolutions.

**How it works:**

- The architecture is an encoder-decoder. The encoder maps input tokens to continuous representations; the decoder generates output tokens autoregressively from those representations.
- The attention mechanism is **Scaled Dot-Product Attention**: queries, keys, and values are projected into vectors; compatibility between a query and all keys is computed via dot product, scaled by √dₖ to prevent vanishing gradients in softmax, then used to weight the values.
- **Multi-Head Attention** runs this process in parallel across 8 "heads" with different learned projections, letting the model jointly attend to different representation subspaces simultaneously.
- Since there's no recurrence, **positional encodings** (sinusoidal functions) are added to embeddings to inject token order information.

**Why it's better than RNNs:**

Self-attention connects all positions in a sequence with a constant number of operations (O(1) sequential ops), versus O(n) for recurrent layers. This dramatically improves parallelizability and makes long-range dependency learning easier.

**Results:** The big Transformer hit 28.4 BLEU on English→German translation — over 2 points better than prior SOTA — and 41.0 on English→French, both at a fraction of the training compute cost of competing models.

**Why it matters:** This is the foundational paper behind every modern LLM. GPT, BERT, and their descendants are all Transformer variants. The architecture's parallelizability is what made large-scale pretraining economically feasible.

