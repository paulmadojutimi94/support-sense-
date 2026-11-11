# Postmortem: "98% accurate" that was really 23%

**Severity:** would have shipped a misleading headline metric in a portfolio README.
**Status:** resolved (process + one code fix). **Date:** 2026-11-11.

## Summary

The first evaluation reported **98.4% top-1 accuracy**. A held-out set, written to look like real user messages, scored **23.1%**. The first number measured how well the engine matched questions written by someone looking at the articles, not how well it helps users. While investigating, I also found a real tokeniser bug: apostrophes split contractions into stray one-letter tokens.

## Timeline

| Step | What happened |
|---|---|
| 1 | Wrote 30 articles, then 70 dev questions, then the ranker. |
| 2 | First eval: 98.4% top-1, 100% precision on High, 0% attack success. |
| 3 | **Detection:** the number was too good for a keyword ranker on 30 short articles. Real-world keyword search usually sits far lower. Treated it as a smell, not a result. |
| 4 | Read the dev questions next to the articles: "wifi sync not working" vs title "Fix Wi-Fi sync problems". The questions reused the articles' own words. |
| 5 | Wrote 30 held-out questions in slang and indirect phrasing ("binned a folder by mistake", "says I've run out of room") **before** running them, and froze them. |
| 6 | Held-out: 23.1% top-1, 38.5% Hit@3. |
| 7 | Inspected the one dev failure, "can't remember my login details". The top result was *App crashes on launch*. Why? `can't` became `can` + `t`, and the stray `t` matched `won't` in that article's tags. |
| 8 | Fixed the tokeniser to drop apostrophes ("can't" → "cant", a stopword). Added regression test `testApostrophesAreDroppedNotSplit`. |
| 9 | Re-ran. The query still fails (the KB never says "remember" or "details"), but the wrong result is now for a defensible reason. Both numbers are reported side by side in the README. |

## Root causes

1. **Eval leakage.** One person wrote the content and the test questions at the same time, so the questions inherited the content's vocabulary. Same pattern as a student writing their own exam.
2. **Tokeniser treated apostrophes as separators.** Common in quick regex tokenisers (`[^a-z0-9]+`). It's invisible until a one-letter fragment matches something. The iOS keyboard's curly apostrophe (’, U+2019) makes it worse, because a naive fix for `'` misses it.

## What went right

- Confidence labels held up under the shift: no wrong answer was ever labelled High on either set, and Low-labelled answers were right only 1 time in 13 on held-out. The **honesty** part of the product works even where the **recall** part doesn't.
- The single failing dev query was investigated rather than tuned away, which surfaced the real bug.

## Fixes and guard rails

| Guard rail | Where |
|---|---|
| Held-out set, frozen, reported next to dev | `eval/holdout.json`, README table |
| "Never tune against holdout" rule for agents and humans | `CLAUDE.md` rule 2 |
| CI quality gate: held-out top-1 ≥ 20%, zero false High on both sets | `EvalTests.testQualityGates` |
| Apostrophes (ASCII + U+2019) dropped before splitting, in both runtimes | `Normalizer.rawTokens`, `reference_ranker.split_ascii_alnum` |
| Regression test named after the symptom | `NormalizerTests.testApostrophesAreDroppedNotSplit` |

## What I'd do differently

Write the held-out questions **first**, ideally from real tickets or by someone who hasn't read the articles, before writing a single article. Then set the success bar before seeing any results.

## Interview soundbite

"My first eval said 98%. I didn't believe it, wrote a blind test set, and got 23%. The gap was vocabulary leakage. The confidence labels were the part that held, since nothing wrong was ever marked High, so I shipped the honest numbers and made the fix (semantic re-ranking) the next milestone with a measurable target."
