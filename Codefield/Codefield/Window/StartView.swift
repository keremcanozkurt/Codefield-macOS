import SwiftUI

struct StartView: View {
    let model: RepositoryWindowModel
    @State private var isTargeted = false
    @State private var dropRefused = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 14) {
                ProductMark()
                Text("Understand a local codebase visually.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
            }

            Button("Open Repository…") { model.chooseRepository() }
                .buttonStyle(QuietButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 32)

            Text(dropRefused ? "Drop a single folder, not files." : "or drag a repository folder here")
                .font(.system(size: 12))
                .foregroundStyle(dropRefused ? Theme.warning : Theme.subtle)
                .padding(.top, 12)
                .animation(.easeOut(duration: 0.15), value: dropRefused)

            if !model.recents.items.isEmpty {
                RecentList(model: model)
                    .padding(.top, 48)
            }

            Spacer(minLength: 40)

            Text("Your source code stays on your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.subtle)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
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
            let accepted = model.openDropped(urls)
            if !accepted { refuseDrop() }
            return accepted
        } isTargeted: { isTargeted = $0 }
    }

    private func refuseDrop() {
        dropRefused = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            dropRefused = false
        }
    }
}

// The logo will sit in front of the name; until it exists the slot is empty.
struct ProductMark: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Codefield")
                .font(.system(size: 40, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Theme.foreground)
        }
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
                Text(location ?? "Not found")
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

    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration, prominent: prominent)
    }

    private struct QuietButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: prominent ? 14 : 12, weight: .medium))
                .foregroundStyle(Theme.foreground)
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
