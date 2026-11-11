import XCTest
@testable import SupportSenseCore

final class NormalizerTests: XCTestCase {
    var normalizer: Normalizer!

    override func setUpWithError() throws {
        normalizer = Normalizer(lexicon: try Lexicon.bundled())
    }

    func testLowercasesAndSplitsOnPunctuation() {
        XCTAssertEqual(Normalizer.rawTokens("Reset PASSWORD, now!"), ["reset", "password", "now"])
    }

    /// Regression for POSTMORTEM.md: "can't" used to become "can" + "t",
    /// and the stray "t" matched "won't" in an unrelated article.
    func testApostrophesAreDroppedNotSplit() {
        XCTAssertEqual(Normalizer.rawTokens("can't won’t"), ["cant", "wont"])   // ASCII + curly
        XCTAssertEqual(normalizer.normalize("I can't log in"), ["login"])
    }

    func testPhrasesMergeBeforeStopwordsAreRemoved() {
        // "in" is a stopword, but "log in" must survive as a phrase.
        XCTAssertEqual(normalizer.normalize("log in"), ["login"])
        XCTAssertEqual(normalizer.normalize("Wi-Fi not working"), ["wifi", "work"])
    }

    func testSynonymsMapToCanonicalTerm() {
        XCTAssertEqual(normalizer.normalize("passcode"), normalizer.normalize("password"))
        XCTAssertEqual(normalizer.normalize("mfa"), ["2fa"])
    }

    func testStemmerConflatesWordForms() {
        XCTAssertEqual(normalizer.stem("charging"), normalizer.stem("charged"))
        XCTAssertEqual(normalizer.stem("charges"), normalizer.stem("charge"))
        XCTAssertEqual(normalizer.stem("batteries"), "battery")
        XCTAssertEqual(normalizer.stem("access"), "access")   // "ss" guard
    }

    func testNonASCIIIsTreatedAsSeparator() {
        XCTAssertEqual(Normalizer.rawTokens("café🔥refund"), ["caf", "refund"])
        XCTAssertEqual(normalizer.normalize("🔥🔥🔥"), [])
    }

    func testStopwordsOnlyNormalisesToNothing() {
        XCTAssertEqual(normalizer.normalize("the a an of to in is it"), [])
    }
}
