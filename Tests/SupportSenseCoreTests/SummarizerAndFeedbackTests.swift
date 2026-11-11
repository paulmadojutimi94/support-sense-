import XCTest
@testable import SupportSenseCore

final class SummarizerTests: XCTestCase {
    func testSplitsSentences() {
        XCTAssertEqual(Summarizer.sentences("One. Two? Three! Four"), ["One.", "Two?", "Three!", "Four"])
        XCTAssertEqual(Summarizer.sentences("Version 1.5 is out."), ["Version 1.5 is out."])  // no split mid-number
    }

    func testPicksMostRelevantSentence() throws {
        let normalizer = Normalizer(lexicon: try Lexicon.bundled())
        let s = Summarizer(normalizer: normalizer)
        let article = Article(id: "X", title: "t", category: "c", tags: [],
                              body: "Intro text here. Refunds reach your card within ten days. Other.")
        XCTAssertEqual(s.summary(of: article, queryTerms: Set(normalizer.normalize("refund card"))),
                       "Refunds reach your card within ten days.")
    }

    func testFallsBackToFirstSentenceAndTruncates() throws {
        let s = Summarizer(normalizer: Normalizer(lexicon: try Lexicon.bundled()), maxLength: 20)
        let article = Article(id: "X", title: "t", category: "c", tags: [],
                              body: "This first sentence is definitely long. Second.")
        XCTAssertEqual(s.summary(of: article, queryTerms: ["zzz"]), "This first sentence…")
    }
}

final class FeedbackStoreTests: XCTestCase {
    func testJSONStoreRoundTripsAcrossInstances() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = JSONFileFeedbackStore(url: url)
        try await store.record(FeedbackEntry(query: "q", articleID: "KB-001", helpful: true, rank: 0, confidence: .high))
        try await store.record(FeedbackEntry(query: "q", articleID: "KB-001", helpful: true, rank: 0, confidence: .high))
        try await store.record(FeedbackEntry(query: "q", articleID: "KB-002", helpful: false, rank: 1, confidence: .low))

        let reopened = JSONFileFeedbackStore(url: url)       // simulates an app relaunch
        let entries = await reopened.entries()
        XCTAssertEqual(entries.count, 3)
        let net = await reopened.netScores()
        XCTAssertEqual(net, ["KB-001": 2, "KB-002": -1])
    }

    func testCorruptFileStartsEmptyInsteadOfCrashing() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = await JSONFileFeedbackStore(url: url).entries()
        XCTAssertEqual(entries, [])
    }
}
