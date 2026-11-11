import Foundation

/// Extractive summary: return the article sentence that shares the most terms
/// with the query. Never invents text, so it can't hallucinate.
public struct Summarizer: Sendable {
    let normalizer: Normalizer
    public let maxLength: Int

    public init(normalizer: Normalizer, maxLength: Int = 180) {
        self.normalizer = normalizer
        self.maxLength = maxLength
    }

    public func summary(of article: Article, queryTerms: Set<String>) -> String {
        let sentences = Self.sentences(article.body)
        guard let first = sentences.first else { return "" }

        var best = first
        var bestOverlap = 0
        for sentence in sentences {
            let overlap = Set(normalizer.normalize(sentence)).intersection(queryTerms).count
            if overlap > bestOverlap {          // strict ">" keeps the earliest on ties
                best = sentence
                bestOverlap = overlap
            }
        }
        return truncate(best)
    }

    /// Splits on . ! ? followed by a space or end of text. Hand-rolled (not
    /// NSLinguisticTagger) so it behaves the same on Linux CI.
    public static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let isEnd = ch == "." || ch == "!" || ch == "?"
            if isEnd && (i + 1 == chars.count || chars[i + 1] == " ") {
                let s = current.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { result.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    func truncate(_ s: String) -> String {
        guard s.count > maxLength else { return s }
        let cut = s.prefix(maxLength)
        let trimmed = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return trimmed.trimmingCharacters(in: .punctuationCharacters) + "…"
    }
}
