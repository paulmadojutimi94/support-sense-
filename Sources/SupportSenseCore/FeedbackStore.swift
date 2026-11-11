import Foundation

/// Where thumbs-up / thumbs-down votes go. A protocol so the app can use a
/// file on disk while tests use memory, and a server could slot in later.
public protocol FeedbackStore: Sendable {
    func record(_ entry: FeedbackEntry) async throws
    func entries() async -> [FeedbackEntry]
}

extension FeedbackStore {
    /// Net votes per article: +1 helpful, -1 not helpful.
    public func netScores() async -> [String: Int] {
        await entries().reduce(into: [:]) { totals, entry in
            totals[entry.articleID, default: 0] += entry.helpful ? 1 : -1
        }
    }
}

/// For tests and previews.
public actor InMemoryFeedbackStore: FeedbackStore {
    private var storage: [FeedbackEntry]

    public init(_ entries: [FeedbackEntry] = []) { storage = entries }

    public func record(_ entry: FeedbackEntry) async throws { storage.append(entry) }
    public func entries() async -> [FeedbackEntry] { storage }
}

/// Persists every vote to a JSON file. An actor, so two quick taps can't
/// interleave and corrupt the file; writes are atomic (temp file + rename).
public actor JSONFileFeedbackStore: FeedbackStore {
    public let url: URL
    private var cache: [FeedbackEntry]

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? Self.decoder.decode([FeedbackEntry].self, from: data) {
            cache = decoded
        } else {
            cache = []   // first launch, or an unreadable file: start clean rather than crash
        }
    }

    public func record(_ entry: FeedbackEntry) async throws {
        let updated = cache + [entry]
        let data = try Self.encoder.encode(updated)
        try data.write(to: url, options: .atomic)
        cache = updated   // only update memory once the disk write succeeded
    }

    public func entries() async -> [FeedbackEntry] { cache }

    /// ~/Library/Application Support/SupportSense/feedback.json on device.
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("SupportSense", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("feedback.json")
    }

    // Computed, not stored: JSONEncoder isn't Sendable, so a shared static
    // instance would trip strict-concurrency checks. Creating one is cheap.
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
