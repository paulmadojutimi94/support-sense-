import Foundation

/// Turns free text into comparable terms:
///   "Can't log in to Wi-Fi!" -> ["login", "wifi"]
///
/// Pipeline (identical in tools/reference_ranker.py):
///   1. lowercase, drop apostrophes, split on anything that isn't a-z / 0-9
///   2. merge multi-word phrases ("wi fi" -> "wifi")
///   3. map synonyms ("passcode" -> "password")
///   4. drop stopwords ("the", "my", "how")
///   5. strip suffixes ("charging" -> "charg")
public struct Normalizer: Sendable {
    public let lexicon: Lexicon
    private let phraseTable: [[String]: String]
    private let maxPhraseLength: Int

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
        var table: [[String]: String] = [:]
        for (key, value) in lexicon.phrases {
            table[key.split(separator: " ").map(String.init)] = value
        }
        self.phraseTable = table
        self.maxPhraseLength = table.keys.map(\.count).max() ?? 1
    }

    public func normalize(_ text: String) -> [String] {
        let raw = Self.rawTokens(text)
        var merged: [String] = []
        merged.reserveCapacity(raw.count)

        var i = 0
        while i < raw.count {
            var matched = false
            let longest = min(maxPhraseLength, raw.count - i)
            for length in stride(from: longest, through: 2, by: -1) {
                if let replacement = phraseTable[Array(raw[i ..< i + length])] {
                    merged.append(replacement)
                    i += length
                    matched = true
                    break
                }
            }
            if !matched {
                merged.append(raw[i])
                i += 1
            }
        }

        var out: [String] = []
        for token in merged {
            let mapped = lexicon.synonyms[token] ?? token
            if lexicon.stopwords.contains(mapped) { continue }
            out.append(stem(mapped))
        }
        return out
    }

    /// Step 1. Walks Unicode scalars (not Characters) so it splits text exactly
    /// like Python's per-code-point loop does.
    public static func rawTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if scalar == "'" || scalar == "\u{2019}" { continue }   // can't -> cant
            let v = scalar.value
            if (97 ... 122).contains(v) || (48 ... 57).contains(v) { // a-z, 0-9
                current.append(scalar)
            } else if !current.isEmpty {
                tokens.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { tokens.append(String(current)) }
        return tokens
    }

    /// Step 5. Rules run in order; each can fire at most once.
    public func stem(_ word: String) -> String {
        var token = word
        for rule in lexicon.stemRules {
            guard token.count >= rule.minLength, token.hasSuffix(rule.suffix) else { continue }
            if !rule.unlessSuffix.isEmpty && token.hasSuffix(rule.unlessSuffix) { continue }
            token = String(token.dropLast(rule.suffix.count)) + rule.replace
        }
        return token
    }
}

extension Array where Element: Hashable {
    /// Removes duplicates, keeping first-seen order (order matters for float sums).
    func uniquedInOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
