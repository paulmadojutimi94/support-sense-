import XCTest
@testable import SupportSenseCore

final class SearchEngineTests: XCTestCase {
    var engine: SearchEngine!

    override func setUpWithError() throws {
        engine = try Fixtures.engine()
    }

    func testObviousQueryRanksRightArticleFirstWithHighConfidence() {
        let result = engine.search("I forgot my password")
        XCTAssertEqual(result.cards.first?.article.id, "KB-001")
        XCTAssertEqual(result.cards.first?.confidence, .high)
    }

    func testEmptyAndJunkInputReturnNoCards() {
        for input in ["", "     ", "🔥🔥🔥💸", "the of and"] {
            XCTAssertTrue(engine.search(input).isEmpty, "expected no cards for \(input.debugDescription)")
        }
    }

    func testOnlyTheTopCardCanBeHigh() {
        let result = engine.search("cancel my subscription")
        XCTAssertFalse(result.cards.dropFirst().contains { $0.confidence == .high })
    }

    func testLimitIsRespected() {
        XCTAssertLessThanOrEqual(engine.search("account", limit: 2).cards.count, 2)
    }

    func testKeywordRepetitionDoesNotInflateScores() {
        let clean = engine.search("password").cards.map { [$0.article.id, "\($0.score)"] }
        let stuffed = engine.search(String(repeating: "password ", count: 50)).cards.map { [$0.article.id, "\($0.score)"] }
        XCTAssertEqual(clean, stuffed)
    }

    func testOversizedQueryIsTruncatedAndFast() {
        let huge = String(repeating: "storage ", count: 2_500)   // 20,000 chars
        let result = engine.search(huge)
        XCTAssertLessThan(result.milliseconds, 250)
        XCTAssertFalse(result.isEmpty)
    }

    func testPositiveFeedbackCanLiftACardButIsCapped() {
        let base = engine.search("charge on my card")
        guard base.cards.count >= 2 else { return XCTFail("need two cards") }
        let runnerUp = base.cards[1]

        let boosted = engine.search("charge on my card", feedback: [runnerUp.article.id: 1_000])
        let lifted = boosted.cards.first { $0.id == runnerUp.id }!
        // 1,000 votes are clamped to feedbackCap -> at most +feedbackWeight (15%).
        XCTAssertEqual(lifted.score, runnerUp.score * (1 + engine.config.feedbackWeight), accuracy: 1e-9)
    }

    func testTiesBreakByArticleIDDeterministically() {
        let a = engine.search("settings").cards.map(\.id)
        let b = engine.search("settings").cards.map(\.id)
        XCTAssertEqual(a, b)
    }

    func testCardsCarrySummaryAndUserFacingMatchedWords() {
        let card = engine.search("battery drains while charging").cards.first!
        XCTAssertEqual(card.article.id, "KB-023")
        XCTAssertFalse(card.summary.isEmpty)
        XCTAssertTrue(card.matchedWords.contains("charging"), "shows the user's word, not the stem 'charg'")
    }

    func testEmptyKnowledgeBaseThrows() throws {
        XCTAssertThrowsError(try SearchEngine(articles: [], lexicon: try Lexicon.bundled())) {
            XCTAssertEqual($0 as? SupportSenseError, .emptyKnowledgeBase)
        }
    }

    func testConfidenceRules() throws {
        let c = engine.config
        XCTAssertEqual(SearchEngine.confidence(rank: 0, score: 9, top: 9, second: 3, coverage: 1, config: c), .high)
        // Same card, but #2 is nearly tied: not High.
        XCTAssertEqual(SearchEngine.confidence(rank: 0, score: 9, top: 9, second: 8.5, coverage: 1, config: c), .medium)
        // Low score even with full coverage: not High.
        XCTAssertEqual(SearchEngine.confidence(rank: 0, score: 1, top: 1, second: nil, coverage: 1, config: c), .medium)
        XCTAssertEqual(SearchEngine.confidence(rank: 3, score: 1, top: 9, second: 8, coverage: 0.3, config: c), .low)
    }
}
