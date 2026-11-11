| Metric | Dev set (63+7 OOS) | Held-out set (26+4 OOS) |
|---|---|---|
| Top-1 accuracy | 98.4% | 23.1% |
| Hit@3 | 98.4% | 38.5% |
| MRR | 0.984 | 0.320 |
| Precision when labelled **High** | 100.0% (40/40) | n/a (0/0) |
| In-scope queries labelled High | 63.5% | 0.0% |
| Out-of-scope wrongly labelled High | 0.0% | 0.0% |

| Shared metric | Value |
|---|---|
| Attack success rate (12 adversarial inputs) | 0.0% |
| Cost per task | $0.00 (on-device, no API calls) |
| Latency p50 / p95 (Python reference, 3000 runs) | 0.024 ms / 0.047 ms |

| Top-card confidence (held-out) | Count | Correct | Accuracy |
|---|---|---|---|
| High | 0 | 0 | n/a |
| Medium | 11 | 5 | 45.5% |
| Low | 13 | 1 | 7.7% |
