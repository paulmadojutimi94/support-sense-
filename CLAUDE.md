# CLAUDE.md — working agreement for agents in this repo

SupportSense: SwiftUI app that answers support questions with ranked cards
from a local knowledge base (BM25 + confidence labels + feedback capture).

## Map
| Path | What | Edit when |
|---|---|---|
| `Sources/SupportSenseCore/` | Ranking engine (pure Swift, no UI) | Changing behaviour |
| `Sources/SupportSenseCore/Resources/lexicon.json` | Stopwords, synonyms, stem rules, **all thresholds** | Tuning |
| `Sources/SupportSenseCore/Resources/knowledge_base.json` | The 30 mock articles | Adding content |
| `App/Sources/` | SwiftUI app (view model + views) | UI work |
| `App/project.yml` | XcodeGen spec; `.xcodeproj` is generated, never committed | New targets/settings |
| `tools/reference_ranker.py` | Python mirror of the engine | **Any** engine change |
| `eval/` | dev, held-out, adversarial sets + generated results | Adding test cases |

## Rules
1. **Engine changes are two-sided.** Change the Swift *and* `tools/reference_ranker.py`,
   then `make eval`. `EvalTests.testSwiftMatchesPythonReference` fails on any drift.
2. **Never tune against `eval/holdout.json`.** Add new cases to `eval/queries.json`.
   If you must add held-out cases, write them *before* looking at results.
3. Numbers live in `lexicon.json`, never as literals in Swift or Python.
4. After `make eval`, paste `eval/RESULTS.md` into the README table and commit
   `eval/golden.json` (CI fails if it is stale).
5. Keep `SearchEngine` a value type with no mutable state.
6. Every bug fix gets a regression test named after the symptom.

## Commands
- `make test` — swift test (macOS or Linux)
- `make eval` — regenerate metrics (Python 3, stdlib only)
- `make open` — generate and open the Xcode project (needs `brew install xcodegen`)
