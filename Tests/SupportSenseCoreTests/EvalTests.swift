import XCTest
@testable import SupportSenseCore

/// Parity + quality gates. These are what keep the README numbers honest.
final class EvalTests: XCTestCase {
    var engine: SearchEngine!

    override func setUpWithError() throws {
        engine = try Fixtures.engine()
    }

    /// Swift must rank and score every eval query exactly like the Python
    /// reference that produced eval/golden.json. If this fails, either the
    /// algorithms drifted or golden.json is stale: run `make eval`.
    func testSwiftMatchesPythonReference() throws {
        let golden: [GoldenEntry] = try Fixtures.load("eval/golden.json")
        XCTAssertGreaterThan(golden.count, 50)
        for entry in golden {
            let cards = Array(engine.search(entry.query).cards.prefix(3))
            XCTAssertEqual(cards.map(\.article.id), entry.top.map(\.id), "ranking drift: \(entry.query)")
            for (card, hit) in zip(cards, entry.top) {
                XCTAssertEqual(card.score, hit.score, accuracy: 1e-9, "score drift: \(entry.query)")
                XCTAssertEqual(card.confidence.rawValue, hit.confidence, "confidence drift: \(entry.query)")
            }
        }
    }

    func testQualityGates() throws {
        let dev: [EvalQuery] = try Fixtures.load("eval/queries.json")
        let holdout: [EvalQuery] = try Fixtures.load("eval/holdout.json")

        XCTAssertGreaterThanOrEqual(top1(dev), 0.95, "dev top-1 regressed")
        XCTAssertGreaterThanOrEqual(top1(holdout), 0.20, "held-out top-1 regressed")

        // The promise the UI makes: "High" is never shown for an off-topic question.
        for q in (dev + holdout) where q.expected == nil {
            XCTAssertNotEqual(engine.search(q.query).topConfidence, .high, "false High: \(q.query)")
        }
        // ...and is never wrong on either set.
        for q in (dev + holdout) where q.expected != nil {
            let top = engine.search(q.query).cards.first
            if top?.confidence == .high {
                XCTAssertEqual(top?.article.id, q.expected, "wrong answer labelled High: \(q.query)")
            }
        }
    }

    func testAdversarialInputsDoNotSucceed() throws {
        let attacks: [AdversarialQuery] = try Fixtures.load("eval/adversarial.json")
        for attack in attacks {
            let text = attack.query == "LONG_INPUT" ? String(repeating: "storage ", count: 2_500) : attack.query
            let result = engine.search(text)
            if let clean = attack.cleanEquivalent {
                XCTAssertEqual(result.cards.map(\.score), engine.search(clean).cards.map(\.score), attack.attack)
            } else {
                XCTAssertFalse(result.cards.contains { $0.confidence == .high }, "\(attack.attack): \(attack.query)")
                XCTAssertLessThan(result.milliseconds, 250, attack.attack)
            }
        }
    }

    /// Prints on-device-class latency. CI logs show the numbers; the assert
    /// only catches a 100x regression, not normal machine noise.
    func testLatencyPercentiles() throws {
        let queries: [EvalQuery] = try Fixtures.load("eval/queries.json")
            + (try Fixtures.load("eval/holdout.json") as [EvalQuery])
        var samples: [Double] = []
        for _ in 0 ..< 30 {
            for q in queries { samples.append(engine.search(q.query).milliseconds) }
        }
        samples.sort()
        let p50 = samples[Int(0.50 * Double(samples.count - 1))]
        let p95 = samples[Int(0.95 * Double(samples.count - 1))]
        print(String(format: "SUPPORTSENSE_LATENCY p50=%.4fms p95=%.4fms n=%d", p50, p95, samples.count))
        XCTAssertLessThan(p95, 5.0)
    }

    private func top1(_ queries: [EvalQuery]) -> Double {
        let inScope = queries.filter { $0.expected != nil }
        let hits = inScope.filter { engine.search($0.query).cards.first?.article.id == $0.expected }
        return Double(hits.count) / Double(inScope.count)
    }
}
