import Foundation
import Observation
import SupportSenseCore

/// All screen state and actions. Views only read properties and call methods,
/// which keeps them dumb and keeps this testable without a simulator.
@MainActor
@Observable
final class SearchViewModel {
    enum Phase: Equatable {
        case idle
        case results
        case noResults
        case failed(String)
    }

    var query = ""
    private(set) var phase: Phase = .idle
    private(set) var result: SearchResult?
    /// Vote cast on each card in the *current* result (articleID -> helpful).
    private(set) var votes: [String: Bool] = [:]
    private(set) var history: [FeedbackEntry] = []

    let suggestions = [
        "I forgot my password",
        "cancel my subscription",
        "app crashes when I open it",
        "my storage is full",
    ]

    @ObservationIgnored private let engine: SearchEngine?
    @ObservationIgnored private let store: any FeedbackStore
    @ObservationIgnored private var netScores: [String: Int] = [:]

    init(engine: SearchEngine?, store: any FeedbackStore, loadError: String? = nil) {
        self.engine = engine
        self.store = store
        if let loadError { phase = .failed(loadError) }
    }

    /// Production wiring: bundled KB + feedback persisted to disk.
    static func live() -> SearchViewModel {
        do {
            let engine = try SearchEngine.bundled()
            let store = JSONFileFeedbackStore(url: try JSONFileFeedbackStore.defaultURL())
            return SearchViewModel(engine: engine, store: store)
        } catch {
            return SearchViewModel(engine: nil, store: InMemoryFeedbackStore(),
                                   loadError: error.localizedDescription)
        }
    }

    func loadFeedback() async {
        history = await store.entries()
        netScores = await store.netScores()
    }

    func submit() {
        guard let engine else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clear(); return }
        let result = engine.search(trimmed, feedback: netScores)
        self.result = result
        votes = [:]
        phase = result.isEmpty ? .noResults : .results
    }

    func use(suggestion: String) {
        query = suggestion
        submit()
    }

    func clear() {
        result = nil
        votes = [:]
        if engine != nil { phase = .idle }
    }

    /// One vote per card per search. The vote shows instantly (optimistic UI)
    /// and is rolled back if the disk write fails.
    func vote(on card: AnswerCard, helpful: Bool) async {
        guard votes[card.id] == nil, let result else { return }
        votes[card.id] = helpful
        let entry = FeedbackEntry(query: result.query, articleID: card.id, helpful: helpful,
                                  rank: card.rank, confidence: card.confidence)
        do {
            try await store.record(entry)
            history.append(entry)
            netScores[card.id, default: 0] += helpful ? 1 : -1   // affects the *next* search only
        } catch {
            votes[card.id] = nil
        }
    }

    var exportJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
