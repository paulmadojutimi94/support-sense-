import Foundation
@testable import SupportSenseCore

/// Shared helpers. Eval files live in <repo>/eval, found relative to this
/// source file so `swift test` works from any working directory.
enum Fixtures {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Fixtures.swift
        .deletingLastPathComponent()   // SupportSenseCoreTests
        .deletingLastPathComponent()   // Tests

    static func load<T: Decodable>(_ relativePath: String, as type: T.Type = T.self) throws -> T {
        let url = repoRoot.appendingPathComponent(relativePath)
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static func engine() throws -> SearchEngine { try SearchEngine.bundled() }
}

struct EvalQuery: Decodable {
    let query: String
    let expected: String?
    let kind: String
}

struct AdversarialQuery: Decodable {
    let query: String
    let attack: String
    let cleanEquivalent: String?
}

struct GoldenEntry: Decodable {
    struct Hit: Decodable { let id: String; let score: Double; let confidence: String }
    let query: String
    let top: [Hit]
}
