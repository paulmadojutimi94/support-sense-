import SwiftUI
import SupportSenseCore

struct ArticleDetailView: View {
    let article: Article

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.category.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(article.title)
                    .font(.title2.bold())
                Text(article.body)
                    .font(.body)
                    .textSelection(.enabled)
                Text(article.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(article.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Proves feedback capture works, and lets you export it for analysis.
struct FeedbackLogView: View {
    let entries: [FeedbackEntry]
    let exportJSON: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("No feedback yet", systemImage: "hand.thumbsup",
                                           description: Text("Votes on answer cards appear here."))
                } else {
                    List(entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: entry.helpful ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                    .foregroundStyle(entry.helpful ? .green : .red)
                                Text(entry.query).font(.subheadline).lineLimit(1)
                            }
                            Text("\(entry.articleID) · #\(entry.rank + 1) · \(entry.confidence.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.createdAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Feedback log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: exportJSON) { Label("Export JSON", systemImage: "square.and.arrow.up") }
                        .disabled(entries.isEmpty)
                }
            }
        }
    }
}
