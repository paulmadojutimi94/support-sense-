import Foundation

/// One help-centre article in the local knowledge base.
public struct Article: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let tags: [String]
    public let body: String

    public init(id: String, title: String, category: String, tags: [String], body: String) {
        self.id = id
        self.title = title
        self.category = category
        self.tags = tags
        self.body = body
    }
}

/// How sure the engine is that a card answers the question.
/// The rules that assign these live in `SearchEngine.confidence(...)`.
public enum Confidence: String, Codable, Sendable, CaseIterable, Comparable {
    case low, medium, high

    private var order: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.order < rhs.order }

    /// Text label. Colour is never the only signal (accessibility).
    public var label: String {
        switch self {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
    }

    /// SF Symbol name, so the badge also differs by shape.
    public var symbolName: String {
        switch self {
        case .high: "checkmark.seal.fill"
        case .medium: "questionmark.circle.fill"
        case .low: "exclamationmark.triangle.fill"
        }
    }
}

/// A ranked answer shown to the user.
public struct AnswerCard: Identifiable, Hashable, Sendable {
    public var id: String { article.id }
    /// 0-based position in the result list.
    public let rank: Int
    public let article: Article
    /// BM25 score after any feedback adjustment.
    public let score: Double
    /// Share of the (normalised) query terms found in this article, 0...1.
    public let coverage: Double
    public let confidence: Confidence
    /// One extractive sentence from the article body.
    public let summary: String
    /// Normalised terms that matched (what the engine saw).
    public let matchedTerms: [String]
    /// The user's own words that matched (what the UI shows).
    public let matchedWords: [String]

    public init(rank: Int, article: Article, score: Double, coverage: Double, confidence: Confidence,
                summary: String, matchedTerms: [String], matchedWords: [String]) {
        self.rank = rank
        self.article = article
        self.score = score
        self.coverage = coverage
        self.confidence = confidence
        self.summary = summary
        self.matchedTerms = matchedTerms
        self.matchedWords = matchedWords
    }
}

/// Everything returned by one search.
public struct SearchResult: Sendable {
    public let query: String
    /// The query after normalisation, in order, de-duplicated.
    public let terms: [String]
    public let cards: [AnswerCard]
    public let duration: Duration

    public var isEmpty: Bool { cards.isEmpty }
    public var topConfidence: Confidence? { cards.first?.confidence }

    public var milliseconds: Double {
        let c = duration.components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1e15
    }
}

/// One thumbs-up / thumbs-down captured from the UI.
public struct FeedbackEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let query: String
    public let articleID: String
    public let helpful: Bool
    public let rank: Int
    public let confidence: Confidence
    public let createdAt: Date

    public init(id: UUID = UUID(), query: String, articleID: String, helpful: Bool,
                rank: Int, confidence: Confidence, createdAt: Date = Date()) {
        self.id = id
        self.query = query
        self.articleID = articleID
        self.helpful = helpful
        self.rank = rank
        self.confidence = confidence
        self.createdAt = createdAt
    }
}
