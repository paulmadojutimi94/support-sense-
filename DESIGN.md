# SupportSense: design doc (one page)

**Goal.** Given a free-text support question, show the most useful help articles first, tell the user honestly how sure we are, and capture whether each answer helped. Ship as a SwiftUI iOS app.

**Constraints.** Local/mock knowledge base (30 articles). Must work offline. Must be explainable in an interview line by line. Must have measurable quality, cost, latency and robustness.

**Non-goals (v1).** Generating new answer text. A server. Learning-to-rank. Multi-language.

## Decisions and the alternatives I rejected

| Decision | Chosen | Alternatives considered | Why rejected |
|---|---|---|---|
| **Retrieval** | BM25 keyword ranking | (a) Plain keyword count (b) On-device embeddings (`NLEmbedding`) (c) Cloud LLM / RAG | (a) Can't tell "refund" (rare, informative) from "account" (everywhere). (b) The right *next* step, but unmeasurable on Linux CI and harder to explain line by line; I wanted a transparent baseline to compare it against first. (c) Costs money per query, needs network, sends user text off-device, adds hallucination and prompt-injection risk. Fails the offline constraint. |
| **Summaries** | Extractive: best-matching sentence | LLM abstractive summary; first sentence always | An abstractive summary can invent steps ("tap Reset in Settings" when there is no such button), which is dangerous in support. First-sentence-always ignores the question. Extractive quotes the article, so it's always true. |
| **Confidence** | Rules on coverage, score, and lead over #2; only the top card can be High | Raw score thresholds; softmax "probabilities"; no labels | BM25 scores aren't comparable across queries (a 3-word query scores higher than a 1-word one), so raw thresholds mislead. Softmax implies a probability we haven't calibrated. Coverage ("did the article contain most of what you asked?") is explainable to a non-engineer and is checked by the eval. |
| **Single source of truth** | All thresholds and word lists in `lexicon.json`, read by Swift *and* Python | Constants in Swift; separate Python config | Two copies drift silently. With one file plus `golden.json` parity, drift is a failing test. |
| **Eval runtime** | Python mirror + Swift parity test | Eval only in Swift tests | No Swift toolchain in every environment (including where this was authored). Python stdlib runs anywhere; parity keeps it honest. The cost is maintaining two implementations, accepted because the engine is ~150 lines. |
| **Feedback storage** | JSON file behind an `actor` and a `FeedbackStore` protocol | Core Data / SwiftData; UserDefaults; server | SwiftData is heavy for an append-only log and harder to test on Linux. UserDefaults isn't for growing data. A server is out of scope; the protocol leaves the door open. |
| **Feedback effect** | Global per-article boost, capped at ±15%, applied to the *next* search | No effect; per-query boost; reorder live | Live reordering moves the card under the user's thumb. Uncapped boosts let a few votes bury the right answer. Per-query is better but needs query clustering (roadmap). |
| **Project file** | XcodeGen `project.yml`; `.xcodeproj` generated | Committed `.xcodeproj`; Swift Playgrounds `.swiftpm` app | `project.pbxproj` merge conflicts are the #1 pain when several agents or people touch one repo. Playgrounds apps limit build settings and CI. |
| **UI state** | `@Observable` `@MainActor` view model | `ObservableObject`/`@Published`; TCA | `@Observable` is the iOS 17 standard with finer-grained updates. TCA is a large dependency for four screens. |

## Confidence rules (lexicon.json → `ranking`)

- **High:** rank #1 **and** ≥75% of query terms found **and** score ≥ 4.0 **and** at least 1.15× the #2 score.
- **Medium:** ≥50% of query terms found **and** score ≥ 50% of the top card's.
- **Low:** everything else. If the best card is Low, the UI shows a "rephrase or contact support" banner.

## Risks

| Risk | Mitigation |
|---|---|
| Dev-set numbers overstate quality | Frozen held-out set, reported next to dev (see POSTMORTEM) |
| Swift/Python drift | `golden.json` parity test to 1e-9; CI fails on stale golden |
| Feedback popularity bias | ±15% cap; per-query feedback on roadmap |
| Hostile input (huge, emoji, injection text) | 500-scalar cap, ASCII tokeniser, no LLM; 12-case adversarial suite in CI |

## How I'll know v2 is better

Held-out top-1 ≥ 60% and Hit@3 ≥ 80%, while precision-when-High stays 100% and out-of-scope false High stays 0%, with p95 latency under 20 ms on an iPhone 12.
