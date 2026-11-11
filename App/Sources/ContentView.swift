import SwiftUI
import SupportSenseCore

@MainActor
struct ContentView: View {
    @State private var model = SearchViewModel.live()
    @State private var showingFeedbackLog = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("SupportSense")
                .searchable(text: $model.query, prompt: "Describe your problem")
                .onSubmit(of: .search) { model.submit() }
                .onChange(of: model.query) { _, newValue in
                    if newValue.isEmpty { model.clear() }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingFeedbackLog = true
                        } label: {
                            Label("Feedback log", systemImage: "list.bullet.clipboard")
                        }
                    }
                }
                .sheet(isPresented: $showingFeedbackLog) {
                    FeedbackLogView(entries: model.history, exportJSON: model.exportJSON)
                }
                .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
                .task { await model.loadFeedback() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            IdleView(suggestions: model.suggestions) { model.use(suggestion: $0) }
        case .noResults:
            ContentUnavailableView.search(text: model.query)
        case .failed(let message):
            ContentUnavailableView("Couldn't load help articles", systemImage: "xmark.octagon",
                                   description: Text(message))
        case .results:
            if let result = model.result {
                ResultsList(result: result, votes: model.votes) { card, helpful in
                    Task { await model.vote(on: card, helpful: helpful) }
                }
            }
        }
    }
}

private struct IdleView: View {
    let suggestions: [String]
    let onPick: (String) -> Void

    var body: some View {
        List {
            Section("Try asking") {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { onPick(suggestion) }
                }
            }
            Section {
                Text("Answers come from a local help library on this device. Nothing you type leaves your phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ResultsList: View {
    let result: SearchResult
    let votes: [String: Bool]
    let onVote: (AnswerCard, Bool) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("\(result.cards.count) answers · \(result.milliseconds, specifier: "%.2f") ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if result.topConfidence == .low {
                    LowConfidenceBanner()
                }

                ForEach(result.cards) { card in
                    AnswerCardView(card: card, vote: votes[card.id]) { helpful in
                        onVote(card, helpful)
                    }
                }
            }
            .padding()
        }
    }
}

/// Shown when even the best match is weak. Honest beats confidently wrong.
private struct LowConfidenceBanner: View {
    var body: some View {
        Label {
            Text("These may not answer your question. Try describing it differently, or contact a support agent.")
        } icon: {
            Image(systemName: "exclamationmark.bubble")
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
}
