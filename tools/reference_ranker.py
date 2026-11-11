"""Reference implementation of the SupportSense ranker, line-for-line with
Sources/SupportSenseCore (Normalizer.swift, BM25Index.swift, SearchEngine.swift).

Why this exists: the evaluation must be runnable anywhere (CI on Linux, a
laptop without Xcode). The Swift test `ParityTests` loads eval/golden.json,
which this file produces, and fails if the Swift engine ranks or scores a
single query differently. So the numbers in the README are guarded twice.

Pure standard library. No third-party imports.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources" / "SupportSenseCore" / "Resources"


# ---------------------------------------------------------------- lexicon
@dataclass
class Lexicon:
    stopwords: set[str]
    phrases: dict[tuple[str, ...], str]
    max_phrase_len: int
    synonyms: dict[str, str]
    stem_rules: list[dict]
    ranking: dict

    @classmethod
    def load(cls, path: Path = RESOURCES / "lexicon.json") -> "Lexicon":
        raw = json.loads(path.read_text())
        phrases = {tuple(k.split(" ")): v for k, v in raw["phrases"].items()}
        return cls(
            stopwords=set(raw["stopwords"]),
            phrases=phrases,
            max_phrase_len=max((len(k) for k in phrases), default=1),
            synonyms=raw["synonyms"],
            stem_rules=raw["stemRules"],
            ranking=raw["ranking"],
        )


# ------------------------------------------------------------- normaliser
APOSTROPHES = {"'", "’"}  # ASCII apostrophe and the typographic one iOS keyboards insert


def split_ascii_alnum(text: str) -> list[str]:
    """Lowercase, then split on every scalar that is not a-z or 0-9.
    Apostrophes are DROPPED, not treated as separators, so "can't" -> "cant"
    (a stopword) instead of "can" + "t" (see POSTMORTEM.md).
    Mirrors Normalizer.rawTokens(_:) which walks unicodeScalars."""
    tokens, current = [], []
    for ch in text.lower():
        if ch in APOSTROPHES:
            continue
        if ("a" <= ch <= "z") or ("0" <= ch <= "9"):
            current.append(ch)
        elif current:
            tokens.append("".join(current))
            current = []
    if current:
        tokens.append("".join(current))
    return tokens


def stem(token: str, rules: list[dict]) -> str:
    for rule in rules:
        suffix = rule["suffix"]
        unless = rule["unlessSuffix"]
        if len(token) >= rule["minLength"] and token.endswith(suffix):
            if unless and token.endswith(unless):
                continue
            token = token[: len(token) - len(suffix)] + rule["replace"]
    return token


def normalize(text: str, lex: Lexicon) -> list[str]:
    raw = split_ascii_alnum(text)
    merged: list[str] = []
    i = 0
    while i < len(raw):
        matched = False
        for length in range(min(lex.max_phrase_len, len(raw) - i), 1, -1):
            key = tuple(raw[i : i + length])
            if key in lex.phrases:
                merged.append(lex.phrases[key])
                i += length
                matched = True
                break
        if not matched:
            merged.append(raw[i])
            i += 1
    out = []
    for tok in merged:
        tok = lex.synonyms.get(tok, tok)
        if tok in lex.stopwords:
            continue
        out.append(stem(tok, lex.stem_rules))
    return out


def unique_in_order(tokens: list[str]) -> list[str]:
    seen, out = set(), []
    for t in tokens:
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


# ------------------------------------------------------------------ index
@dataclass
class Article:
    id: str
    title: str
    category: str
    tags: list[str]
    body: str


@dataclass
class Index:
    lex: Lexicon
    articles: list[Article]
    term_freqs: list[dict[str, int]] = field(default_factory=list)
    lengths: list[int] = field(default_factory=list)
    doc_freq: dict[str, int] = field(default_factory=dict)
    avg_len: float = 0.0

    @classmethod
    def build(cls, articles: list[Article], lex: Lexicon) -> "Index":
        idx = cls(lex=lex, articles=articles)
        r = lex.ranking
        for a in articles:
            tokens = (
                normalize(a.title, lex) * r["titleWeight"]
                + normalize(" ".join(a.tags), lex) * r["tagWeight"]
                + normalize(a.body, lex)
            )
            tf: dict[str, int] = {}
            for t in tokens:
                tf[t] = tf.get(t, 0) + 1
            idx.term_freqs.append(tf)
            idx.lengths.append(len(tokens))
            for t in tf:
                idx.doc_freq[t] = idx.doc_freq.get(t, 0) + 1
        idx.avg_len = sum(idx.lengths) / len(articles) if articles else 0.0
        return idx

    def idf(self, term: str) -> float:
        n = len(self.articles)
        df = self.doc_freq.get(term, 0)
        return math.log(1.0 + (n - df + 0.5) / (df + 0.5))

    def score(self, doc: int, terms: list[str]) -> float:
        k1, b = self.lex.ranking["k1"], self.lex.ranking["b"]
        tf_map, dl = self.term_freqs[doc], self.lengths[doc]
        total = 0.0
        for t in terms:
            tf = tf_map.get(t, 0)
            if tf == 0:
                continue
            denom = tf + k1 * (1.0 - b + b * dl / self.avg_len)
            total += self.idf(t) * (tf * (k1 + 1.0)) / denom
        return total


# ----------------------------------------------------------------- search
@dataclass
class Card:
    article_id: str
    score: float
    coverage: float
    confidence: str
    matched: list[str]


def confidence_for(rank: int, score: float, top: float, second: float | None,
                   coverage: float, r: dict) -> str:
    relative = score / top if top > 0 else 0.0
    margin = (top / second) if second and second > 0 else math.inf
    if (rank == 0 and coverage >= r["highCoverage"] and score >= r["highMinScore"]
            and margin >= r["highMinMargin"]):
        return "high"
    if coverage >= r["mediumCoverage"] and relative >= r["mediumRelative"]:
        return "medium"
    return "low"


def search(index: Index, query: str, limit: int | None = None,
           feedback: dict[str, int] | None = None) -> list[Card]:
    r = index.lex.ranking
    limit = limit or r["defaultLimit"]
    query = query[: r["maxQueryCharacters"]]
    terms = unique_in_order(normalize(query, index.lex))
    if not terms:
        return []
    feedback = feedback or {}
    scored = []
    for d, art in enumerate(index.articles):
        s = index.score(d, terms)
        if s <= 0:
            continue
        net = max(-r["feedbackCap"], min(r["feedbackCap"], feedback.get(art.id, 0)))
        s *= 1.0 + r["feedbackWeight"] * net / r["feedbackCap"]
        matched = [t for t in terms if t in index.term_freqs[d]]
        scored.append((s, art.id, matched))
    scored.sort(key=lambda x: (-x[0], x[1]))
    scored = scored[:limit]
    if not scored:
        return []
    top = scored[0][0]
    second = scored[1][0] if len(scored) > 1 else None
    cards = []
    for rank, (s, aid, matched) in enumerate(scored):
        cov = len(matched) / len(terms)
        cards.append(Card(aid, s, cov, confidence_for(rank, s, top, second, cov, r), matched))
    return cards


def load_index() -> Index:
    lex = Lexicon.load()
    raw = json.loads((RESOURCES / "knowledge_base.json").read_text())
    arts = [Article(a["id"], a["title"], a["category"], a["tags"], a["body"]) for a in raw]
    return Index.build(arts, lex)
