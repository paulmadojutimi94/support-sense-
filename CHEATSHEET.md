# SupportSense cheatsheet: every line, explained

Read this with the code open side by side. Each block quotes the code, then explains **what** it does and **why** it's written that way. Interview-style questions are at the end.

**The whole app in one analogy.** A librarian (the engine) gets your question. She crosses out filler words, standardises spellings (the normaliser), checks the card catalogue for which books mention your words and how unusual those words are (BM25), photocopies the most relevant sentence from each book (the summariser), and tells you honestly how sure she is (confidence). You tell her if it helped (feedback). Next time she leans slightly toward books people liked.

---

## 1. `Package.swift`

```swift
// swift-tools-version: 5.9
```
The first line is not a comment to SwiftPM: it sets the manifest API version. 5.9 is needed for `@Observable` (macros) and is what Xcode 15 ships.

```swift
import PackageDescription
let package = Package(
    name: "SupportSenseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
```
Minimum OS versions. iOS 17 for `@Observable` and `ContentUnavailableView`; macOS 14 so `swift test` on a Mac sees the same APIs. Linux ignores `platforms`.

```swift
    products: [.library(name: "SupportSenseCore", targets: ["SupportSenseCore"])],
```
What other code (the iOS app) can import.

```swift
    targets: [
        .target(name: "SupportSenseCore", resources: [.process("Resources")]),
```
The engine. `resources` copies the two JSON files into a bundle that code reaches via `Bundle.module`. `.process` may optimise files; for JSON it just copies them.

```swift
        .testTarget(name: "SupportSenseCoreTests", dependencies: ["SupportSenseCore"])
```
XCTest target. **Why a package at all?** The engine has zero UI code, so it builds and tests on Linux CI in seconds, with no simulator.

---

## 2. `Resources/lexicon.json`

| Key | Meaning |
|---|---|
| `stopwords` | Words too common to help ("the", "my", "how"). Removed. Includes `cant`, `dont`, `wont`, which only works because apostrophes are dropped first (see POSTMORTEM). |
| `phrases` | Multi-word expressions merged into one token **before** stopwords are removed: `"log in"` → `login`. Otherwise "in" would be deleted as a stopword and "log" alone means nothing. |
| `synonyms` | One-way maps to a canonical word: `passcode` → `password`, `subscription` → `plan`. Applied to the query **and** the articles, so both sides speak the same vocabulary. |
| `stemRules` | Ordered suffix rules. Each fires at most once, in order. `minLength` stops short words being mangled ("thing" keeps its "ing"). `unlessSuffix: "ss"` stops "access" → "acces". |
| `ranking.k1` = 1.2 | BM25 saturation. How quickly repeating a word stops adding score. 1.2 is the textbook default. |
| `ranking.b` = 0.75 | BM25 length normalisation. 0 = ignore article length, 1 = fully penalise long articles. Textbook default. |
| `titleWeight`, `tagWeight` = 2 | Title and tag words are counted twice: a word in the title is stronger evidence than one in passing. |
| `maxQueryCharacters` = 500 | Hard cap to bound work on hostile input. |
| `highCoverage`, `highMinScore`, `highMinMargin` | The three tests for a High label (section 8). |
| `mediumCoverage`, `mediumRelative` | The two tests for Medium. |
| `feedbackWeight` = 0.15, `feedbackCap` = 3 | Votes change scores by at most ±15%, reached at ±3 net votes. |

**Why JSON instead of Swift constants?** The Python mirror reads the same file. One source of truth means the two can't drift.

---

## 3. `Models.swift`

```swift
public struct Article: Codable, Hashable, Identifiable, Sendable {
```
- `Codable`: can be decoded from `knowledge_base.json` automatically (property names match JSON keys).
- `Hashable`: needed for `NavigationLink(value:)` / `.navigationDestination(for: Article.self)`.
- `Identifiable`: provides `id` so SwiftUI `ForEach` can track items.
- `Sendable`: safe to pass between threads/actors. All fields are immutable value types, so this is free.

```swift
    public init(id: String, title: String, ...)
```
Swift's automatic memberwise init is `internal`. The app is a different module, so a `public init` is written by hand.

```swift
public enum Confidence: String, Codable, Sendable, CaseIterable, Comparable {
    case low, medium, high
```
`String` raw values (`"high"`) are what's stored in feedback JSON and compared in the parity test. `Comparable` lets code ask `confidence >= .medium`.

```swift
    private var order: Int { switch self { case .low: 0 ... } }
    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.order < rhs.order }
```
`Comparable` needs `<`. Ranking by an explicit number is safer than relying on declaration order.

```swift
    public var label: String { ... "High confidence" ... }
    public var symbolName: String { ... "checkmark.seal.fill" ... }
```
Text and icon live in the model so every screen labels consistently. Three signals (colour, word, shape) because colour alone fails colour-blind users (WCAG 1.4.1).

```swift
public struct AnswerCard: Identifiable, Hashable, Sendable {
    public var id: String { article.id }
```
A card's identity is its article. Computed, so it can't get out of sync.

```swift
    public let rank: Int        // 0-based position
    public let score: Double    // BM25 after feedback
    public let coverage: Double // share of query terms found, 0...1
    public let confidence: Confidence
    public let summary: String
    public let matchedTerms: [String]  // engine's view: "charg"
    public let matchedWords: [String]  // user's view: "charging"
```
Two "matched" lists: stems are what the engine compares, but showing "charg" to a user looks broken.

```swift
public struct SearchResult: Sendable {
    public let query: String
    public let terms: [String]
    public let cards: [AnswerCard]
    public let duration: Duration
    public var isEmpty: Bool { cards.isEmpty }
    public var topConfidence: Confidence? { cards.first?.confidence }
```
`Duration` (Swift 5.7+) is a precise, unit-safe time span. `topConfidence` is optional because there may be no cards.

```swift
    public var milliseconds: Double {
        let c = duration.components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1e15
    }
```
`Duration` stores seconds + attoseconds (10⁻¹⁸ s). 1 ms = 10¹⁵ attoseconds.

```swift
public struct FeedbackEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let query, articleID: String
    public let helpful: Bool
    public let rank: Int
    public let confidence: Confidence
    public let createdAt: Date
```
Stores the **context** of the vote (rank and confidence at the time), not just the vote. Later you can ask "do people thumbs-down High cards?", which is a calibration check from real users. Default arguments (`id: UUID = UUID()`, `createdAt: Date = Date()`) keep call sites short and let tests inject fixed values.

---

## 4. `Lexicon.swift`

```swift
public struct StemRule: Codable, Hashable, Sendable { suffix, replace, minLength, unlessSuffix }
public struct RankingConfig: Codable, Hashable, Sendable { k1, b, ... }
```
Typed mirrors of the JSON. If the JSON has a typo'd key or wrong type, decoding throws at launch, not silently mid-search.

```swift
public struct Lexicon: Codable, Sendable {
    public let stopwords: Set<String>
```
Decoded from a JSON array straight into a `Set`, so lookups are O(1). The JSON's `_comment` and `version` extras: unknown keys are ignored by `Codable`; `version` is decoded for future migrations.

```swift
    public static func load(from url: URL) throws -> Lexicon {
        try JSONDecoder().decode(Lexicon.self, from: Data(contentsOf: url))
    }
    public static func bundled() throws -> Lexicon { try load(from: BundledResource.url("lexicon")) }
```
Two entry points: tests and tools can load any file; the app loads the bundled one.

```swift
public enum KnowledgeBase { ... decode([Article].self ...) }
```
A caseless `enum` is a namespace: it can't be instantiated by accident.

```swift
public enum SupportSenseError: Error, LocalizedError, Equatable {
    case missingResource(String)
    case emptyKnowledgeBase
    public var errorDescription: String? { ... }
```
`LocalizedError` gives the human message the app shows in its error screen. `Equatable` lets tests assert the exact error.

```swift
enum BundledResource {
    static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw SupportSenseError.missingResource(name)
        }
        return url
    }
}
```
`Bundle.module` is generated by SwiftPM for targets with resources. `guard ... else throw` turns "file missing" into a clear error instead of a crash.

---

## 5. `Normalizer.swift`: text → terms

```swift
public struct Normalizer: Sendable {
    public let lexicon: Lexicon
    private let phraseTable: [[String]: String]
    private let maxPhraseLength: Int
```
The phrase table is keyed by an **array of words** (`["log","in"]`), because matching happens on tokens, not raw text. That avoids the classic bug where replacing the substring "log in" also hits "catalog in".

```swift
    public init(lexicon: Lexicon) {
        var table: [[String]: String] = [:]
        for (key, value) in lexicon.phrases {
            table[key.split(separator: " ").map(String.init)] = value
        }
        self.phraseTable = table
        self.maxPhraseLength = table.keys.map(\.count).max() ?? 1
    }
```
Built once, at init. `max() ?? 1` handles an empty phrase list. `map(String.init)` converts `Substring` slices into owned `String`s.

```swift
    public func normalize(_ text: String) -> [String] {
        let raw = Self.rawTokens(text)
        var merged: [String] = []
        merged.reserveCapacity(raw.count)
```
Step 1, then prepare the output array. `reserveCapacity` avoids repeated reallocations (micro-optimisation, harmless).

```swift
        var i = 0
        while i < raw.count {
            var matched = false
            let longest = min(maxPhraseLength, raw.count - i)
            for length in stride(from: longest, through: 2, by: -1) {
                if let replacement = phraseTable[Array(raw[i ..< i + length])] {
                    merged.append(replacement); i += length; matched = true; break
                }
            }
            if !matched { merged.append(raw[i]); i += 1 }
        }
```
Step 2: **greedy longest match**. At each position, try the longest phrase first, down to 2 words. If none match, keep the single word. `stride(... through: 2, by: -1)` is empty when fewer than 2 words remain, so the loop safely does nothing.

```swift
        var out: [String] = []
        for token in merged {
            let mapped = lexicon.synonyms[token] ?? token
            if lexicon.stopwords.contains(mapped) { continue }
            out.append(stem(mapped))
        }
        return out
```
Steps 3 to 5, in that order. Synonyms before stopwords, so a synonym can never map *into* a stopword unnoticed. Stemming last, so the stopword list holds normal words, not stems.

```swift
    public static func rawTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if scalar == "'" || scalar == "\u{2019}" { continue }
            let v = scalar.value
            if (97 ... 122).contains(v) || (48 ... 57).contains(v) {
                current.append(scalar)
            } else if !current.isEmpty {
                tokens.append(String(current)); current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { tokens.append(String(current)) }
        return tokens
    }
```
Step 1. Key interview points:
- **Unicode scalars, not `Character`s.** A Swift `Character` can be several code points (e.g. "é" written as e + accent). Python iterates code points. Walking scalars makes Swift split **identically** to Python, which the parity test depends on.
- **97...122 = a–z, 48...57 = 0–9** (ASCII codes). Everything else is a separator. This also neutralises emoji and injection syntax.
- **Apostrophes are skipped, not treated as separators**: `can't` → `cant`. `\u{2019}` is the curly ’ that iOS's smart punctuation inserts. This is the postmortem fix.
- `static` because it needs no lexicon; the engine reuses it to map stems back to user words.

```swift
    public func stem(_ word: String) -> String {
        var token = word
        for rule in lexicon.stemRules {
            guard token.count >= rule.minLength, token.hasSuffix(rule.suffix) else { continue }
            if !rule.unlessSuffix.isEmpty && token.hasSuffix(rule.unlessSuffix) { continue }
            token = String(token.dropLast(rule.suffix.count)) + rule.replace
        }
        return token
    }
```
Step 5. A tiny rule-based stemmer (a simplified Porter stemmer). Rules run **sequentially on the evolving word**: "charges" → (s) "charge" → (e) "charg"; "charging" → (ing) "charg". Both meet at "charg". Stems needn't be real words, only consistent. `token.count` counts Characters, which equals bytes here because tokens are pure ASCII.

```swift
extension Array where Element: Hashable {
    func uniquedInOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
```
De-duplicate while keeping first-seen order. `Set.insert` returns `(inserted: Bool, ...)`: true the first time. **Order matters** because floating-point addition isn't perfectly associative; summing terms in the same order as Python keeps scores bit-identical. De-duplicating is also the keyword-stuffing defence: "password ×50" becomes one "password".

---

## 6. `BM25Index.swift`: scoring

**BM25 in plain English.** For each word in your question: *how rare is this word across all articles* (rare = informative) × *how often it appears in this article* (with diminishing returns) ÷ *a penalty if this article is unusually long*. Add up across words.

```swift
public struct BM25Index: Sendable {
    public let articles: [Article]
    let termFrequencies: [[String: Int]]  // per article: word → count
    let lengths: [Int]                    // per article: total tokens
    let documentFrequency: [String: Int]  // word → how many articles contain it
    let averageLength: Double
    let config: RankingConfig
```
Classic **inverted-index statistics**, precomputed once so each search is just lookups and arithmetic.

```swift
    public init(articles: [Article], normalizer: Normalizer) {
        ...
        for article in articles {
            let title = normalizer.normalize(article.title)
            let tags = normalizer.normalize(article.tags.joined(separator: " "))
            let body = normalizer.normalize(article.body)
            let tokens = Array(repeating: title, count: config.titleWeight).flatMap { $0 }
                + Array(repeating: tags, count: config.tagWeight).flatMap { $0 }
                + body
```
Field weighting by **repetition**: the title appears twice in the token list, so its words get higher term frequency. Simpler than BM25F (per-field BM25) and good enough for 30 articles. `flatMap { $0 }` flattens `[[String]]` into `[String]`.

```swift
            var tf: [String: Int] = [:]
            for token in tokens { tf[token, default: 0] += 1 }
            for term in tf.keys { df[term, default: 0] += 1 }
```
`tf` counts each word in this article. `df` increments **once per article** per distinct word (iterating `tf.keys`, not `tokens`).

```swift
        self.averageLength = articles.isEmpty ? 0 : Double(lengths.reduce(0, +)) / Double(articles.count)
```
Average article length for the `b` normalisation. Guarded against divide-by-zero (the engine also refuses an empty KB).

```swift
    func idf(_ term: String) -> Double {
        let n = Double(articles.count)
        let df = Double(documentFrequency[term] ?? 0)
        return log(1.0 + (n - df + 0.5) / (df + 0.5))
    }
```
Inverse document frequency, BM25+ style (the `1.0 +` inside `log` keeps it positive even for words in every article). A word in 1 of 30 articles scores ~3.0; a word in 25 of 30 scores ~0.2.

```swift
    func score(document d: Int, terms: [String]) -> Double {
        let k1 = config.k1, b = config.b
        let tfMap = termFrequencies[d]
        let dl = Double(lengths[d])
        var total = 0.0
        for term in terms {
            guard let count = tfMap[term], count > 0 else { continue }
            let tf = Double(count)
            let denominator = tf + k1 * (1.0 - b + b * dl / averageLength)
            total += idf(term) * (tf * (k1 + 1.0)) / denominator
        }
        return total
    }
```
The BM25 formula. `tf * (k1+1) / (tf + k1 * ...)` rises fast then flattens: the 1st mention matters most, the 10th barely. `(1 - b + b * dl/avg)` is >1 for long articles, shrinking their score. **The exact operator order matches Python** so results agree to the last bit.

```swift
    func contains(_ term: String, inDocument d: Int) -> Bool { termFrequencies[d][term] != nil }
```
Used to compute coverage and matched words.

---

## 7. `Summarizer.swift`

```swift
public func summary(of article: Article, queryTerms: Set<String>) -> String {
    let sentences = Self.sentences(article.body)
    guard let first = sentences.first else { return "" }
    var best = first; var bestOverlap = 0
    for sentence in sentences {
        let overlap = Set(normalizer.normalize(sentence)).intersection(queryTerms).count
        if overlap > bestOverlap { best = sentence; bestOverlap = overlap }
    }
    return truncate(best)
}
```
Pick the sentence sharing the most distinct query terms. Strict `>` keeps the **earliest** sentence on ties (earlier sentences in help articles tend to be the instructions). If nothing overlaps, `best` stays the first sentence: a sensible lead.

```swift
public static func sentences(_ text: String) -> [String] { ... }
```
Splits after `.`, `!` or `?` **only when followed by a space or end of text**, so "1.5" and "e.g.x" don't split. Hand-rolled because Apple's `NSLinguisticTagger`/`NLTokenizer` isn't on Linux.

```swift
func truncate(_ s: String) -> String {
    guard s.count > maxLength else { return s }
    let cut = s.prefix(maxLength)
    let trimmed = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
    return trimmed.trimmingCharacters(in: .punctuationCharacters) + "…"
}
```
Cut at the last whole word before 180 characters, strip a dangling comma, add an ellipsis. `.map` on an optional index: if there's a space, cut there, otherwise keep the hard cut.

---

## 8. `SearchEngine.swift`: the orchestrator

```swift
public struct SearchEngine: Sendable {
    public let index: BM25Index
    public let normalizer: Normalizer
    public let summarizer: Summarizer
    public var config: RankingConfig { normalizer.lexicon.ranking }
```
A **value type with only `let`s**. No locks needed: it can be used from any thread. The config is derived, not stored twice.

```swift
    public init(articles: [Article], lexicon: Lexicon) throws {
        guard !articles.isEmpty else { throw SupportSenseError.emptyKnowledgeBase }
```
Fail fast. An empty KB would make `averageLength` 0 and every score NaN.

```swift
    public func search(_ query: String, limit: Int? = nil, feedback: [String: Int] = [:]) -> SearchResult {
        let clock = ContinuousClock()
        let start = clock.now
```
`ContinuousClock` is monotonic: unaffected by the user changing the system time. Good for measuring.

```swift
        let scalars = query.unicodeScalars.prefix(config.maxQueryCharacters)
        let bounded = String(String.UnicodeScalarView(scalars))
        let terms = normalizer.normalize(bounded).uniquedInOrder()
```
1. Cap at 500 **scalars** (matching Python's `query[:500]`). A 20,000-character paste can't slow anything down.
2. Normalise and de-duplicate.

```swift
        guard !terms.isEmpty else { return SearchResult(query: query, terms: [], cards: [], duration: clock.now - start) }
```
Empty, whitespace, emoji or stopword-only input returns nothing, early.

```swift
        struct Scored { let doc: Int; let score: Double; let matched: [String] }
        var scored: [Scored] = []
        for d in index.articles.indices {
            var s = index.score(document: d, terms: terms)
            guard s > 0 else { continue }
```
Score every article. For 30 articles a linear scan takes microseconds; posting lists would only add complexity. Articles with zero overlap are dropped, so a nonsense query produces no cards rather than five random ones.

```swift
            let id = index.articles[d].id
            let net = max(-config.feedbackCap, min(config.feedbackCap, feedback[id] ?? 0))
            s *= 1.0 + config.feedbackWeight * Double(net) / Double(config.feedbackCap)
```
Feedback: clamp net votes to [-3, 3], scale to [-15%, +15%]. With no votes this multiplies by exactly 1.0, so eval scores are untouched.

```swift
            scored.append(Scored(doc: d, score: s, matched: terms.filter { index.contains($0, inDocument: d) }))
        }
        scored.sort {
            $0.score != $1.score ? $0.score > $1.score
                                 : index.articles[$0.doc].id < index.articles[$1.doc].id
        }
        let top = Array(scored.prefix(limit ?? config.defaultLimit))
```
Sort by score descending; ties broken by article ID so results are **deterministic** (Swift's sort isn't stable, and flaky order would break the parity test).

```swift
        let topScore = top.first?.score ?? 0
        let secondScore = top.count > 1 ? top[1].score : nil
        let termSet = Set(terms)
        let cards = top.enumerated().map { rank, item in
            let article = index.articles[item.doc]
            let coverage = Double(item.matched.count) / Double(terms.count)
            return AnswerCard(rank: rank, article: article, score: item.score, coverage: coverage,
                confidence: Self.confidence(...), summary: summarizer.summary(of: article, queryTerms: termSet),
                matchedTerms: item.matched, matchedWords: matchedWords(in: bounded, matched: Set(item.matched)))
        }
```
Build cards. **Coverage** = what fraction of your question's meaningful words this article contains. Summaries are only computed for the ≤5 cards shown, not all 30 articles.

```swift
    public static func confidence(rank:score:top:second:coverage:config:) -> Confidence {
        let relative = top > 0 ? score / top : 0
        let margin: Double
        if let second, second > 0 { margin = top / second } else { margin = .infinity }
        if rank == 0, coverage >= config.highCoverage, score >= config.highMinScore, margin >= config.highMinMargin { return .high }
        if coverage >= config.mediumCoverage, relative >= config.mediumRelative { return .medium }
        return .low
    }
```
`static` and pure: testable with made-up numbers, no engine needed.
- **High** needs all four: it's #1; it covers ≥75% of your words; the score is strong in absolute terms (≥4, so a one-word match can't qualify); and it leads #2 by ≥15% (no near-ties).
- **Medium**: covers half your words and is at least half as strong as #1.
- **Low**: everything else.
- `margin = .infinity` when there's only one result, so a lone strong card can still be High.

```swift
    func matchedWords(in query: String, matched: Set<String>) -> [String] {
        Normalizer.rawTokens(query)
            .filter { word in normalizer.normalize(word).contains(where: matched.contains) }
            .uniquedInOrder()
    }
```
For each word the user typed, normalise it alone; keep it if its stem is among the matched terms. Shows "charging", not "charg". Limitation: two-word phrases ("wi fi") don't map back.

---

## 9. `FeedbackStore.swift`

```swift
public protocol FeedbackStore: Sendable {
    func record(_ entry: FeedbackEntry) async throws
    func entries() async -> [FeedbackEntry]
}
```
**Dependency inversion.** The view model depends on this protocol, not a file. Tests use memory; a future server store can drop in. `async` because real stores do I/O; `throws` because writes can fail.

```swift
extension FeedbackStore {
    public func netScores() async -> [String: Int] {
        await entries().reduce(into: [:]) { totals, entry in totals[entry.articleID, default: 0] += entry.helpful ? 1 : -1 }
    }
}
```
A default implementation every store gets for free. `reduce(into:)` mutates one dictionary instead of copying it each step.

```swift
public actor InMemoryFeedbackStore: FeedbackStore { private var storage: [FeedbackEntry] ... }
```
An **actor** serialises access to its state: two simultaneous votes can't corrupt the array. Actors are automatically `Sendable`.

```swift
public actor JSONFileFeedbackStore: FeedbackStore {
    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? Self.decoder.decode([FeedbackEntry].self, from: data) { cache = decoded }
        else { cache = [] }
    }
```
Load once into memory. A missing **or corrupt** file starts empty rather than crashing the app (a deliberate trade: losing an analytics log beats a crash loop). Tested by `testCorruptFileStartsEmptyInsteadOfCrashing`.

```swift
    public func record(_ entry: FeedbackEntry) async throws {
        let updated = cache + [entry]
        let data = try Self.encoder.encode(updated)
        try data.write(to: url, options: .atomic)
        cache = updated
    }
```
- `.atomic` writes to a temp file then renames, so a crash mid-write never leaves half a JSON file.
- Memory is updated **only after** the disk write succeeds: memory and disk never disagree.
- Rewriting the whole file each vote is O(n). Fine for thousands of votes; at scale you'd append lines (JSONL) or use SQLite.

```swift
    public static func defaultURL() throws -> URL { ... applicationSupportDirectory/SupportSense/feedback.json }
```
Application Support is Apple's place for app-managed data the user doesn't browse (unlike Documents). It's backed up and not purged like Caches.

```swift
    static var encoder: JSONEncoder { ... .iso8601, [.prettyPrinted, .sortedKeys] }
    static var decoder: JSONDecoder { ... .iso8601 }
```
**Computed** properties, not `static let`: `JSONEncoder` isn't `Sendable`, so a shared static instance would raise strict-concurrency errors. ISO-8601 dates are human-readable and sortable. Sorted keys keep diffs stable.

---

## 10. The SwiftUI app (`App/Sources`)

### `SupportSenseApp.swift`
`@main` marks the entry point. `WindowGroup { ContentView() }` is the root scene.

### `SearchViewModel.swift`
```swift
@MainActor
@Observable
final class SearchViewModel {
```
- `@MainActor`: all state changes happen on the main thread, where UI must update.
- `@Observable` (iOS 17 Observation framework): SwiftUI re-renders only views that **read** a changed property. Finer-grained than `ObservableObject`, and no `@Published` boilerplate.
- `final`: no subclassing, which allows small compiler optimisations and states intent.

```swift
    enum Phase: Equatable { case idle, results, noResults, failed(String) }
```
A single **state machine** instead of several booleans (`isLoading`, `hasError`...) that could contradict each other. Impossible states can't be represented.

```swift
    var query = ""
    private(set) var phase: Phase = .idle
    private(set) var result: SearchResult?
    private(set) var votes: [String: Bool] = [:]
    private(set) var history: [FeedbackEntry] = []
```
`private(set)`: views can read but only the model can write. `query` is writable because the search field binds to it.

```swift
    @ObservationIgnored private let engine: SearchEngine?
    @ObservationIgnored private let store: any FeedbackStore
    @ObservationIgnored private var netScores: [String: Int] = [:]
```
`@ObservationIgnored`: these never drive UI, so don't track them. `any FeedbackStore` is an existential: any concrete store fits. `engine` is optional so a failed load still shows an error screen.

```swift
    static func live() -> SearchViewModel {
        do { ... return SearchViewModel(engine: engine, store: store) }
        catch { return SearchViewModel(engine: nil, store: InMemoryFeedbackStore(), loadError: error.localizedDescription) }
    }
```
**Composition root**: the one place real dependencies are wired. Previews and tests can build the model with fakes.

```swift
    func loadFeedback() async { history = await store.entries(); netScores = await store.netScores() }
```
Called from `.task` when the screen appears. Restores votes from previous launches.

```swift
    func submit() {
        guard let engine else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clear(); return }
        let result = engine.search(trimmed, feedback: netScores)
        self.result = result; votes = [:]
        phase = result.isEmpty ? .noResults : .results
    }
```
Synchronous: a search takes microseconds, so there's no loading spinner or background hop. Votes reset per search so new cards are votable.

```swift
    func vote(on card: AnswerCard, helpful: Bool) async {
        guard votes[card.id] == nil, let result else { return }
        votes[card.id] = helpful
        let entry = FeedbackEntry(query: result.query, articleID: card.id, helpful: helpful, rank: card.rank, confidence: card.confidence)
        do { try await store.record(entry); history.append(entry); netScores[card.id, default: 0] += helpful ? 1 : -1 }
        catch { votes[card.id] = nil }
    }
```
- One vote per card per search (`guard votes[card.id] == nil`): no double counting from double taps.
- **Optimistic UI**: the filled thumb shows instantly, then rolls back if saving fails.
- `netScores` updates for the **next** search, so cards don't jump under the user's finger.

```swift
    var exportJSON: String { ... }
```
The log as pretty JSON for `ShareLink`.

### `ContentView.swift`
```swift
@MainActor
struct ContentView: View {
    @State private var model = SearchViewModel.live()
```
`@State` owns the `@Observable` model for the view's lifetime. `@MainActor` because `live()` is main-actor isolated.

```swift
        NavigationStack {
            content
                .navigationTitle("SupportSense")
                .searchable(text: $model.query, prompt: "Describe your problem")
                .onSubmit(of: .search) { model.submit() }
```
`.searchable` gives the native iOS search bar. `$model.query` is a two-way binding. Searching **on submit** (not every keystroke) keeps the feedback log meaningful: each logged query is a complete question.

```swift
                .onChange(of: model.query) { _, newValue in if newValue.isEmpty { model.clear() } }
```
Tapping the ✕ in the search bar returns to the suggestions screen. Two-parameter closure (old, new) is the iOS 17 API.

```swift
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingFeedbackLog = true } label: { Label("Feedback log", systemImage: "list.bullet.clipboard") } } }
                .sheet(isPresented: $showingFeedbackLog) { FeedbackLogView(...) }
                .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
                .task { await model.loadFeedback() }
```
Toolbar button opens the log as a sheet. Value-based navigation: any `NavigationLink(value: article)` lands on the detail view. `.task` runs async work on appear and cancels it on disappear.

```swift
    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle: IdleView(...)
        case .noResults: ContentUnavailableView.search(text: model.query)
        case .failed(let message): ContentUnavailableView("Couldn't load help articles", ...)
        case .results: if let result = model.result { ResultsList(...) }
        }
    }
```
One `switch` over the state machine: every state has exactly one screen. `ContentUnavailableView` is the iOS 17 standard empty state.

`IdleView`: suggestion buttons plus a privacy note. `ResultsList`: a header with count and timing (`specifier: "%.2f"` formats to 2 decimals), the `LowConfidenceBanner` when the top card is Low, then cards in a `LazyVStack` (builds rows only when on screen). `LowConfidenceBanner` uses `.accessibilityElement(children: .combine)` so VoiceOver reads it as one sentence.

### `AnswerCardView.swift`
- Header row: rank `#1`, category, `ConfidenceBadge`.
- `NavigationLink(value: card.article)` with `.buttonStyle(.plain)` so the title doesn't turn blue.
- Summary and "Matched:" line.
- Vote buttons: `.frame(minWidth: 44, minHeight: 44)` meets Apple's minimum tap target; `.disabled(vote != nil)` after voting; `.accessibilityLabel("Helpful")` because VoiceOver can't describe an icon; `.accessibilityAddTraits(.isSelected)` announces the chosen vote; `.sensoryFeedback(.success, trigger:)` adds a haptic (iOS 17).
- `ConfidenceBadge`: `Label` (icon + text) tinted green/blue/orange with a translucent capsule background.
- `#Preview` renders a sample card in Xcode's canvas, which is why `AnswerCard` needed a public init.

### `DetailAndLogViews.swift`
- `ArticleDetailView`: full article with `.textSelection(.enabled)` so users can copy steps.
- `FeedbackLogView`: newest first (`entries.reversed()`), relative timestamps (`style: .relative` → "2 min ago"), `ShareLink` to export JSON, `@Environment(\.dismiss)` for the Done button.

### `App/project.yml`
XcodeGen generates the `.xcodeproj` from this file. Notable settings: `GENERATE_INFOPLIST_FILE: YES` (no Info.plist to maintain), `INFOPLIST_KEY_UILaunchScreen_Generation` (blank launch screen without a storyboard), `SWIFT_STRICT_CONCURRENCY: complete` (surfaces data-race risks at compile time), local package dependency `path: ..`.

---

## 11. Tests (`Tests/SupportSenseCoreTests`)

| Test | Proves |
|---|---|
| `Fixtures.repoRoot` | Uses `#filePath` to find `eval/` from any working directory |
| `testApostrophesAreDroppedNotSplit` | Postmortem regression: `can't` → `cant`, both apostrophe styles |
| `testPhrasesMergeBeforeStopwordsAreRemoved` | "log in" survives although "in" is a stopword |
| `testStemmerConflatesWordForms` | charging/charged/charges → same stem; "access" untouched |
| `testNonASCIIIsTreatedAsSeparator` | emoji-only input → no terms |
| `testOnlyTheTopCardCanBeHigh` | the UI contract |
| `testKeywordRepetitionDoesNotInflateScores` | "password" ×50 = "password" exactly |
| `testOversizedQueryIsTruncatedAndFast` | 20k chars handled in < 250 ms |
| `testPositiveFeedbackCanLiftACardButIsCapped` | 1,000 votes = +15%, not more |
| `testTiesBreakByArticleIDDeterministically` | same input, same order |
| `testConfidenceRules` | each High/Medium/Low boundary with synthetic numbers |
| `testJSONStoreRoundTripsAcrossInstances` | votes survive an "app relaunch" |
| `testSwiftMatchesPythonReference` | every eval query: same top-3 IDs, scores within 1e-9, same labels |
| `testQualityGates` | dev ≥ 95%, held-out ≥ 20%, no false High, no wrong High |
| `testAdversarialInputsDoNotSucceed` | the 12 attacks |
| `testLatencyPercentiles` | prints `SUPPORTSENSE_LATENCY p50/p95`; fails if p95 > 5 ms |

---

## 12. Python mirror (`tools/`)

- `reference_ranker.py` is the same five-step normaliser, BM25 and confidence rules, written to match Swift operator for operator. `split_ascii_alnum` iterates code points (= Swift scalars). `scored.sort(key=lambda x: (-x[0], x[1]))` = score desc, ID asc.
- `eval.py` runs dev, held-out and adversarial sets, measures latency (`time.perf_counter`), and writes `results.json`, `RESULTS.md` and `golden.json`. Percentiles use nearest-rank.
- CI runs `eval.py`, then `git diff --exit-code eval/golden.json`: if someone changed the engine without regenerating, CI fails.

---

## 13. Likely interview questions

**Why not just use an LLM?** Cost per query, network dependency, privacy (support questions contain personal details), and hallucinated instructions. For a fixed help library, retrieval plus extractive summaries is cheaper, faster, private and can't invent steps. I'd add an LLM only for rewriting the user's question, behind the same eval.

**Your held-out accuracy is 23%. Isn't that bad?** Yes, for recall, and I say so in the README. The point is the measurement was honest and the confidence labels held: zero wrong answers marked High. The next milestone has a concrete target (60%) and a known fix (semantic re-ranking) for the known failure (vocabulary mismatch).

**How do you know Swift and Python agree?** `golden.json` stores every query's top-3 IDs, scores and labels from Python; a Swift test compares to 1e-9. Both read one `lexicon.json`. Tokenising by Unicode scalars and summing in the same order makes it bit-for-bit.

**Why is only the top card allowed to be High?** "High" means "this is your answer." Two Highs would contradict each other.

**How does it scale to 100,000 articles?** Replace the linear scan with posting lists (only articles containing a query word are scored), keep the precomputed stats, and move to embeddings with an approximate-nearest-neighbour index for semantics. Feedback moves to SQLite or a server.

**How would you test the UI?** The view model is plain Swift with injectable dependencies, so most logic is unit-testable without a simulator. Add XCUITests for the search → vote → log flow, and snapshot tests for the three badge states in light/dark and large Dynamic Type.

**What's the thread-safety story?** Engine: immutable value type, safe anywhere. Feedback: actors serialise access. UI state: `@MainActor`. Strict concurrency checking is on.
