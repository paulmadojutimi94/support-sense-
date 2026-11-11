import Foundation

/// The one public entry point: query in, ranked answer cards out.
/// A value type with no mutable state, so it is safe to share across threads.
public struct SearchEngine: Sendable {
    public let index: BM25Index
    public let normalizer: Normalizer
    public let summarizer: Summarizer
    public var config: RankingConfig { normalizer.lexicon.ranking }

    public init(articles: [Article], lexicon: Lexicon) throws {
        guard !articles.isEmpty else { throw SupportSenseError.emptyKnowledgeBase }
        let normalizer = Normalizer(lexicon: lexicon)
        self.normalizer = normalizer
        self.index = BM25Index(articles: articles, normalizer: normalizer)
        self.summarizer = Summarizer(normalizer: normalizer)
    }

    /// Engine over the bundled mock knowledge base.
    public static func bundled() throws -> SearchEngine {
        try SearchEngine(articles: KnowledgeBase.bundled(), lexicon: Lexicon.bundled())
    }

    /// - Parameters:
    ///   - feedback: net helpful votes per article ID (+1 per thumbs-up,
    ///     -1 per thumbs-down). Clamped to ±feedbackCap, so at most ±15% score.
    public func search(_ query: String, limit: Int? = nil,
                       feedback: [String: Int] = [:]) -> SearchResult {
        let clock = ContinuousClock()
        let start = clock.now

        // Truncate by Unicode scalars to match Python's code-point slicing.
        let scalars = query.unicodeScalars.prefix(config.maxQueryCharacters)
        let bounded = String(String.UnicodeScalarView(scalars))
        let terms = normalizer.normalize(bounded).uniquedInOrder()

        guard !terms.isEmpty else {
            return SearchResult(query: query, terms: [], cards: [], duration: clock.now - start)
        }

        // 1. Score every article (30 docs: a linear scan beats any cleverness).
        struct Scored { let doc: Int; let score: Double; let matched: [String] }
        var scored: [Scored] = []
        for d in index.articles.indices {
            var s = index.score(document: d, terms: terms)
            guard s > 0 else { continue }
            let id = index.articles[d].id
            let net = max(-config.feedbackCap, min(config.feedbackCap, feedback[id] ?? 0))
            s *= 1.0 + config.feedbackWeight * Double(net) / Double(config.feedbackCap)
            scored.append(Scored(doc: d, score: s, matched: terms.filter { index.contains($0, inDocument: d) }))
        }

        // 2. Sort by score, then ID, so ties are deterministic.
        scored.sort {
            $0.score != $1.score ? $0.score > $1.score
                                 : index.articles[$0.doc].id < index.articles[$1.doc].id
        }
        let top = Array(scored.prefix(limit ?? config.defaultLimit))

        // 3. Label confidence and build cards.
        let topScore = top.first?.score ?? 0
        let secondScore = top.count > 1 ? top[1].score : nil
        let termSet = Set(terms)
        let cards = top.enumerated().map { rank, item in
            let article = index.articles[item.doc]
            let coverage = Double(item.matched.count) / Double(terms.count)
            return AnswerCard(
                rank: rank,
                article: article,
                score: item.score,
                coverage: coverage,
                confidence: Self.confidence(rank: rank, score: item.score, top: topScore,
                                            second: secondScore, coverage: coverage, config: config),
                summary: summarizer.summary(of: article, queryTerms: termSet),
                matchedTerms: item.matched,
                matchedWords: matchedWords(in: bounded, matched: Set(item.matched))
            )
        }
        return SearchResult(query: query, terms: terms, cards: cards, duration: clock.now - start)
    }

    /// High   = top card only, covers >=75% of the query, strong score, clear lead over #2.
    /// Medium = covers >=50% of the query and scores >=50% of the top card.
    /// Low    = anything else. The UI tells the user to rephrase or contact support.
    public static func confidence(rank: Int, score: Double, top: Double, second: Double?,
                                  coverage: Double, config: RankingConfig) -> Confidence {
        let relative = top > 0 ? score / top : 0
        let margin: Double
        if let second, second > 0 { margin = top / second } else { margin = .infinity }

        if rank == 0, coverage >= config.highCoverage, score >= config.highMinScore,
           margin >= config.highMinMargin {
            return .high
        }
        if coverage >= config.mediumCoverage, relative >= config.mediumRelative {
            return .medium
        }
        return .low
    }

    /// Maps matched (stemmed) terms back to the words the user actually typed,
    /// so the UI says "Matched: charging" rather than "Matched: charg".
    func matchedWords(in query: String, matched: Set<String>) -> [String] {
        Normalizer.rawTokens(query)
            .filter { word in normalizer.normalize(word).contains(where: matched.contains) }
            .uniquedInOrder()
    }
}
