import SwiftUI

// The questions and answers come from faq.json, which the web build writes
// from Web/src/product.ts: the same list the workspace page shows in its own
// full-screen help, kept in one place.
nonisolated struct FAQContent: Decodable, Equatable, Sendable {
    struct Entry: Decodable, Equatable, Hashable, Sendable {
        var question: String
        var answer: String
    }

    var supportURL: URL
    var supportNote: String
    var entries: [Entry]

    static func load(from bundle: Bundle = .main) -> FAQContent? {
        let url = bundle.url(forResource: "faq", withExtension: "json")
            ?? bundle.url(forResource: "faq", withExtension: "json", subdirectory: "Workspace")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FAQContent.self, from: data)
    }
}

struct FAQView: View {
    private let content = FAQContent.load()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Frequently asked questions")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(content?.entries ?? [], id: \.self) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.question)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.foreground)
                            Text(Self.withCode(entry.answer))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 14)
                        Divider()
                    }
                }
                .padding(.horizontal, 24)
            }

            if let content {
                HStack(spacing: 4) {
                    Text(content.supportNote)
                        .foregroundStyle(Theme.subtle)
                    Button("Support Codefield") { ExternalLinks.open(content.supportURL) }
                        .buttonStyle(.link)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 560)
    }

    // Answers mark code with backticks, as upstream's FAQ does.
    static func withCode(_ text: String) -> AttributedString {
        var result = AttributedString()
        for (index, part) in text.split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            var piece = AttributedString(String(part))
            if index % 2 == 1 {
                piece.font = .system(size: 12, design: .monospaced)
                piece.foregroundColor = Theme.foreground
            }
            result += piece
        }
        return result
    }
}
