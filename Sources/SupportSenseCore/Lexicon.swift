import Foundation

/// One suffix-stripping rule, e.g. "ing" -> "" for words of 6+ letters.
public struct StemRule: Codable, Hashable, Sendable {
    public let suffix: String
    public let replace: String
    public let minLength: Int
    /// Skip the rule if the word ends with this (e.g. don't strip the "s" from "access").
    public let unlessSuffix: String
}

/// Every tunable number in the ranker. Loaded from lexicon.json.
public struct RankingConfig: Codable, Hashable, Sendable {
    public let k1: Double
    public let b: Double
    public let titleWeight: Int
    public let tagWeight: Int
    public let maxQueryCharacters: Int
    public let defaultLimit: Int
    public let highCoverage: Double
    public let highMinScore: Double
    public let highMinMargin: Double
    public let mediumCoverage: Double
    public let mediumRelative: Double
    public let feedbackWeight: Double
    public let feedbackCap: Int
}

/// Text-normalisation tables + ranking config. The same JSON is read by
/// tools/reference_ranker.py, which is how Swift and Python stay in lock-step.
public struct Lexicon: Codable, Sendable {
    public let version: Int
    public let stopwords: Set<String>
    public let phrases: [String: String]
    public let synonyms: [String: String]
    public let stemRules: [StemRule]
    public let ranking: RankingConfig

    public static func load(from url: URL) throws -> Lexicon {
        try JSONDecoder().decode(Lexicon.self, from: Data(contentsOf: url))
    }

    public static func bundled() throws -> Lexicon {
        try load(from: BundledResource.url("lexicon"))
    }
}

public enum KnowledgeBase {
    public static func load(from url: URL) throws -> [Article] {
        try JSONDecoder().decode([Article].self, from: Data(contentsOf: url))
    }

    public static func bundled() throws -> [Article] {
        try load(from: BundledResource.url("knowledge_base"))
    }
}

public enum SupportSenseError: Error, LocalizedError, Equatable {
    case missingResource(String)
    case emptyKnowledgeBase

    public var errorDescription: String? {
        switch self {
        case .missingResource(let name): "Bundled resource \(name).json is missing."
        case .emptyKnowledgeBase: "The knowledge base has no articles."
        }
    }
}

enum BundledResource {
    static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw SupportSenseError.missingResource(name)
        }
        return url
    }
}
