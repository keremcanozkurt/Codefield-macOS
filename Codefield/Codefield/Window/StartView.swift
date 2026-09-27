import SwiftUI

struct StartView: View {
    let model: RepositoryWindowModel
    @State private var isTargeted = false
    @State private var refusal: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 14) {
                ProductMark()
                Text("Understand a local codebase visually.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
            }

            HStack(spacing: 10) {
                Button("Open Repository…") { model.chooseRepository() }
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                Button("Clone Git Repository…") { model.showClone() }
                    .buttonStyle(QuietButtonStyle(prominent: true, secondary: true))
            }
            .padding(.top, 32)

            Text(refusal ?? "or drag a repository folder here")
                .font(.system(size: 12))
                .foregroundStyle(refusal == nil ? Theme.subtle : Theme.warning)
                .padding(.top, 12)
                .animation(.easeOut(duration: 0.15), value: refusal)

            if !model.recents.items.isEmpty {
                RecentList(model: model)
                    .padding(.top, 48)
            }

            Spacer(minLength: 40)

            HStack(spacing: 14) {
                Button("FAQ") { model.showFAQ() }
                Button("Support") { ExternalLinks.open(ExternalLinks.support) }
                    .help("Help with using Codefield")
                Button("Support Codefield", systemImage: "heart") { ExternalLinks.open(ExternalLinks.donation) }
                    .labelStyle(.iconOnly)
                    .help("Support Codefield")
                Spacer()
                Text("Your source code stays on your Mac.")
                    .foregroundStyle(Theme.subtle)
            }
            .buttonStyle(FooterLinkStyle())
            .font(.system(size: 11))
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.foreground.opacity(0.02)))
                .padding(12)
                .opacity(isTargeted ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: isTargeted)
                .allowsHitTesting(false)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let result = model.openDropped(urls)
            if let message = result.refusal { refuse(message) }
            return result == .opened
        } isTargeted: { isTargeted = $0 }
    }

    private func refuse(_ message: String) {
        refusal = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if refusal == message { refusal = nil }
        }
    }
}

private struct FooterLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterLink(configuration: configuration)
    }

    private struct FooterLink: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovered || configuration.isPressed ? Theme.foreground : Theme.muted)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

// The symbol and wordmark are vector images in the asset catalog, drawn in
// the page's foreground color.
struct ProductMark: View {
    var body: some View {
        HStack(spacing: 18) {
            Image("CodefieldMark")
                .resizable()
                .scaledToFit()
                .frame(height: 54)
            Image("CodefieldWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 36)
        }
        .foregroundStyle(Theme.foreground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codefield")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct RecentList: View {
    let model: RepositoryWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent repositories")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.subtle)
                Spacer()
                Button("Clear") { model.recents.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtle)
                    .help("Clear the list of recent repositories")
            }
            .padding(.horizontal, 10)

            VStack(spacing: 2) {
                ForEach(model.recents.items) { item in
                    RecentRow(item: item, location: model.recents.location(of: item)) {
                        model.openRecent(item)
                    } remove: {
                        model.recents.remove(item)
                    }
                }
            }
        }
        .frame(maxWidth: 460)
    }
}

private struct RecentRow: View {
    let item: RecentRepository
    let location: String?
    let open: () -> Void
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(location == nil ? Theme.subtle : Theme.foreground)
                    .lineLimit(1)
                Text(location ?? "Not available")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.foreground.opacity(isHovered ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button("Open", action: open)
            Button("Remove from Recent Repositories", action: remove)
        }
        .help(location ?? "")
    }
}

// Matches the page's buttons: a thin border that strengthens on hover.
struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    var secondary = false

    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration, prominent: prominent, secondary: secondary)
    }

    private struct QuietButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let secondary: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: prominent ? 14 : 12, weight: .medium))
                .foregroundStyle(secondary && !isHovered ? Theme.muted : Theme.foreground)
                .padding(.horizontal, prominent ? 18 : 12)
                .frame(height: prominent ? 36 : 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(configuration.isPressed ? Theme.foreground.opacity(0.08) : Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isHovered ? Theme.lineStrong : Theme.line)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
    }
}
