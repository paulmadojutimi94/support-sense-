import Foundation

/// Okapi BM25 over title (x titleWeight) + tags (x tagWeight) + body.
///
///   score(doc, query) = sum over query terms t of
///       idf(t) * tf * (k1 + 1) / (tf + k1 * (1 - b + b * docLen / avgDocLen))
///
/// idf rewards rare words ("refund" beats "account"), the tf part rewards
/// repetition with diminishing returns (k1), and b penalises long articles.
public struct BM25Index: Sendable {
    public let articles: [Article]
    let termFrequencies: [[String: Int]]
    let lengths: [Int]
    let documentFrequency: [String: Int]
    let averageLength: Double
    let config: RankingConfig

    public init(articles: [Article], normalizer: Normalizer) {
        let config = normalizer.lexicon.ranking
        var tfs: [[String: Int]] = []
        var lengths: [Int] = []
        var df: [String: Int] = [:]

        for article in articles {
            let title = normalizer.normalize(article.title)
            let tags = normalizer.normalize(article.tags.joined(separator: " "))
            let body = normalizer.normalize(article.body)
            let tokens = Array(repeating: title, count: config.titleWeight).flatMap { $0 }
                + Array(repeating: tags, count: config.tagWeight).flatMap { $0 }
                + body

            var tf: [String: Int] = [:]
            for token in tokens { tf[token, default: 0] += 1 }
            for term in tf.keys { df[term, default: 0] += 1 }
            tfs.append(tf)
            lengths.append(tokens.count)
        }

        self.articles = articles
        self.termFrequencies = tfs
        self.lengths = lengths
        self.documentFrequency = df
        self.averageLength = articles.isEmpty ? 0 : Double(lengths.reduce(0, +)) / Double(articles.count)
        self.config = config
    }

    func idf(_ term: String) -> Double {
        let n = Double(articles.count)
        let df = Double(documentFrequency[term] ?? 0)
        return log(1.0 + (n - df + 0.5) / (df + 0.5))
    }

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

    func contains(_ term: String, inDocument d: Int) -> Bool {
        termFrequencies[d][term] != nil
    }
}
