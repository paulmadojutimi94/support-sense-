"""Run the SupportSense evaluation and write:
  eval/results.json  - machine-readable metrics (CI diffs this)
  eval/RESULTS.md    - the table pasted into the README
  eval/golden.json   - per-query top-3 ids + scores; Swift ParityTests asserts against it

Usage:  python3 tools/eval.py            (from repo root)
"""
from __future__ import annotations

import json
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from reference_ranker import ROOT, load_index, search  # noqa: E402

EVAL = ROOT / "eval"
LONG_INPUT = "storage " * 2500  # 20,000 characters


def pct(values: list[float], p: float) -> float:
    ordered = sorted(values)
    k = max(0, min(len(ordered) - 1, round(p / 100 * (len(ordered) - 1))))
    return ordered[k]


def evaluate(index, queries: list[dict]) -> tuple[dict, list[dict]]:
    in_scope = [q for q in queries if q["expected"]]
    oos = [q for q in queries if not q["expected"]]
    top1 = hit3 = 0
    rr_sum = 0.0
    failures, golden = [], []
    buckets = {"high": [0, 0], "medium": [0, 0], "low": [0, 0]}  # [count, correct]
    oos_false_high = []
    for q in queries:
        cards = search(index, q["query"])
        golden.append({"query": q["query"],
                       "top": [{"id": c.article_id, "score": c.score, "confidence": c.confidence}
                               for c in cards[:3]]})
        ids = [c.article_id for c in cards]
        if not q["expected"]:
            if cards and cards[0].confidence == "high":
                oos_false_high.append(q["query"])
            continue
        top1 += int(bool(ids) and ids[0] == q["expected"])
        hit3 += int(q["expected"] in ids[:3])
        if q["expected"] in ids:
            rr_sum += 1.0 / (ids.index(q["expected"]) + 1)
        if cards:
            b = buckets[cards[0].confidence]
            b[0] += 1
            b[1] += int(ids[0] == q["expected"])
        if not ids or ids[0] != q["expected"]:
            failures.append({"query": q["query"], "kind": q["kind"], "expected": q["expected"],
                             "got": ids[:3], "confidence": cards[0].confidence if cards else None})
    n = len(in_scope)
    high_n, high_ok = buckets["high"]
    metrics = {
        "in_scope_queries": n,
        "out_of_scope_queries": len(oos),
        "top1_accuracy": round(top1 / n, 4),
        "hit_at_3": round(hit3 / n, 4),
        "mrr": round(rr_sum / n, 4),
        "high_conf_precision": round(high_ok / high_n, 4) if high_n else None,
        "high_conf_count": high_n,
        "high_conf_correct": high_ok,
        "high_conf_coverage": round(high_n / n, 4),
        "oos_false_high_rate": round(len(oos_false_high) / len(oos), 4) if oos else None,
        "oos_false_high": oos_false_high,
        "confidence_buckets": {k: {"count": v[0], "correct": v[1]} for k, v in buckets.items()},
        "failures": failures,
    }
    return metrics, golden


def run_attacks(index, attacks: list[dict]) -> list[dict]:
    rows = []
    for a in attacks:
        text = LONG_INPUT if a["query"] == "LONG_INPUT" else a["query"]
        t0 = time.perf_counter()
        try:
            cards, crashed = search(index, text), False
        except Exception as exc:  # pragma: no cover - this is the point of the test
            cards, crashed = [], repr(exc)
        ms = (time.perf_counter() - t0) * 1000
        if "cleanEquivalent" in a:
            clean = search(index, a["cleanEquivalent"])
            same = [(c.article_id, c.score) for c in cards] == [(c.article_id, c.score) for c in clean]
            success = (not same) or bool(crashed)
        else:
            success = bool(crashed) or any(c.confidence == "high" for c in cards) or ms > 250
        rows.append({"attack": a["attack"], "query": a["query"][:60], "success": success,
                     "top": cards[0].article_id if cards else None,
                     "confidence": cards[0].confidence if cards else None, "ms": round(ms, 3)})
    return rows


def main() -> int:
    index = load_index()
    sets = {"dev": json.loads((EVAL / "queries.json").read_text()),
            "holdout": json.loads((EVAL / "holdout.json").read_text())}
    attacks = json.loads((EVAL / "adversarial.json").read_text())

    metrics, golden = {}, []
    for name, qs in sets.items():
        metrics[name], g = evaluate(index, qs)
        golden.extend(g)
    attack_rows = run_attacks(index, attacks)
    asr = sum(r["success"] for r in attack_rows) / len(attack_rows)

    timings = []
    all_queries = sets["dev"] + sets["holdout"]
    for _ in range(30):
        for q in all_queries:
            t0 = time.perf_counter()
            search(index, q["query"])
            timings.append((time.perf_counter() - t0) * 1000)
    latency = {"p50": round(pct(timings, 50), 4), "p95": round(pct(timings, 95), 4),
               "samples": len(timings)}

    results = {"kb_articles": len(index.articles), "sets": metrics,
               "adversarial_queries": len(attacks), "attack_success_rate": round(asr, 4),
               "attacks": attack_rows, "cost_per_task_usd": 0.0,
               "latency_ms_python_reference": latency}
    (EVAL / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    (EVAL / "golden.json").write_text(json.dumps(golden, indent=2) + "\n")

    def p(x):
        return "n/a" if x is None else f"{x * 100:.1f}%"

    d, h = metrics["dev"], metrics["holdout"]
    lines = [
        f"| Metric | Dev set ({d['in_scope_queries']}+{d['out_of_scope_queries']} OOS) | "
        f"Held-out set ({h['in_scope_queries']}+{h['out_of_scope_queries']} OOS) |",
        "|---|---|---|",
        f"| Top-1 accuracy | {p(d['top1_accuracy'])} | {p(h['top1_accuracy'])} |",
        f"| Hit@3 | {p(d['hit_at_3'])} | {p(h['hit_at_3'])} |",
        f"| MRR | {d['mrr']:.3f} | {h['mrr']:.3f} |",
        f"| Precision when labelled **High** | {p(d['high_conf_precision'])} ({d['high_conf_correct']}/{d['high_conf_count']}) | "
        f"{p(h['high_conf_precision'])} ({h['high_conf_correct']}/{h['high_conf_count']}) |",
        f"| In-scope queries labelled High | {p(d['high_conf_coverage'])} | {p(h['high_conf_coverage'])} |",
        f"| Out-of-scope wrongly labelled High | {p(d['oos_false_high_rate'])} | {p(h['oos_false_high_rate'])} |",
        "",
        "| Shared metric | Value |",
        "|---|---|",
        f"| Attack success rate ({len(attacks)} adversarial inputs) | {p(asr)} |",
        "| Cost per task | $0.00 (on-device, no API calls) |",
        f"| Latency p50 / p95 (Python reference, {latency['samples']} runs) | "
        f"{latency['p50']:.3f} ms / {latency['p95']:.3f} ms |",
        "",
        "| Top-card confidence (held-out) | Count | Correct | Accuracy |",
        "|---|---|---|---|",
    ]
    for k in ("high", "medium", "low"):
        c, ok = h["confidence_buckets"][k]["count"], h["confidence_buckets"][k]["correct"]
        lines.append(f"| {k.title()} | {c} | {ok} | {p(ok / c) if c else 'n/a'} |")
    (EVAL / "RESULTS.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    for name in sets:
        print(f"\n{name} failures ({len(metrics[name]['failures'])}):")
        for f in metrics[name]["failures"]:
            print(f"  [{f['kind']}] {f['query']!r} expected {f['expected']} got {f['got']} ({f['confidence']})")
        print("  OOS false High:", metrics[name]["oos_false_high"])
    print("\nAttacks:")
    for r in attack_rows:
        print(f"  {'FAIL' if r['success'] else 'ok  '} {r['attack']:<22} top={r['top']} conf={r['confidence']} {r['ms']}ms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
