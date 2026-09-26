import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.repositoryWindow) private var window
    @Environment(\.openWindow) private var openWindow
    let recents: RecentRepositoryStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Repository…") {
                if let window { window.chooseRepository() } else { openWindow(id: CodefieldApp.windowID) }
            }
            .keyboardShortcut("o")

            Menu("Open Recent") {
                ForEach(recents.items) { item in
                    Button(item.name) { window?.openRecent(item) }
                }
                if !recents.items.isEmpty {
                    Divider()
                    Button("Clear Menu") { recents.clear() }
                }
            }
            .disabled(window == nil || recents.items.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Button("Analyze Again") { window?.analyzeAgain() }
                .keyboardShortcut("r")
                .disabled(window?.repository == nil || window?.isAnalyzing == true)
            Divider()
        }

        // Replaces the text-editing Find submenu, whose ⌘F would otherwise
        // compete with finding a file.
        CommandGroup(replacing: .textEditing) {
            Button("Find File") { window?.focusSearch() }
                .keyboardShortcut("f")
                .disabled(window?.isRevealed != true)
        }

        CommandGroup(replacing: .help) {
            Button("Codefield FAQ") { window?.showFAQ() }
                .disabled(window?.isRevealed != true)
            Button("Support Codefield") { ExternalLinks.open(ExternalLinks.support) }
        }
    }
}
