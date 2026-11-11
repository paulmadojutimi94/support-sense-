import SwiftUI
import SupportSenseCore

struct AnswerCardView: View {
    let card: AnswerCard
    /// nil = not voted yet.
    let vote: Bool?
    let onVote: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(card.rank + 1)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(card.article.category.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ConfidenceBadge(confidence: card.confidence)
            }

            NavigationLink(value: card.article) {
                HStack {
                    Text(card.article.title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Text(card.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !card.matchedWords.isEmpty {
                Text("Matched: \(card.matchedWords.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text(vote == nil ? "Was this helpful?" : "Thanks for the feedback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                voteButton(helpful: true, symbol: "hand.thumbsup", label: "Helpful")
                voteButton(helpful: false, symbol: "hand.thumbsdown", label: "Not helpful")
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func voteButton(helpful: Bool, symbol: String, label: String) -> some View {
        let selected = vote == helpful
        return Button {
            onVote(helpful)
        } label: {
            Image(systemName: selected ? symbol + ".fill" : symbol)
                .imageScale(.large)
                .frame(minWidth: 44, minHeight: 44)   // Apple HIG minimum tap target
        }
        .disabled(vote != nil)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.success, trigger: selected)
    }
}

struct ConfidenceBadge: View {
    let confidence: Confidence

    var body: some View {
        Label(confidence.label, systemImage: confidence.symbolName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private var tint: Color {
        switch confidence {
        case .high: .green
        case .medium: .blue
        case .low: .orange
        }
    }
}

#Preview {
    let article = Article(id: "KB-001", title: "Reset a forgotten password", category: "Account",
                          tags: ["password"], body: "Tap Forgot Password on the login screen.")
    let card = AnswerCard(rank: 0, article: article, score: 7.2, coverage: 1, confidence: .high,
                          summary: "Tap Forgot Password on the login screen.",
                          matchedTerms: ["password"], matchedWords: ["password"])
    return AnswerCardView(card: card, vote: nil) { _ in }.padding()
}
