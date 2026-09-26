//
//  ContentView.swift
//  Codefield
//
//  Created by Kerem Can Özkurt on 26.09.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var model = RepositoryWindowModel()

    var body: some View {
        Group {
            if model.repository == nil {
                StartView(model: model)
            } else {
                WorkspaceView(model: model)
            }
        }
        .frame(minWidth: 1024, minHeight: 640)
        .background(Theme.background)
        .navigationTitle(model.repository?.name ?? "Codefield")
        .navigationSubtitle(model.subtitle)
        .toolbar { WindowToolbar(model: model) }
        .toolbarBackground(Theme.background, for: .windowToolbar)
        .focusedSceneValue(\.repositoryWindow, model)
        .preferredColorScheme(.dark)
        .alert(
            "Could not open the folder",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .onDisappear { model.close() }
    }
}

private struct WindowToolbar: ToolbarContent {
    let model: RepositoryWindowModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.repository != nil {
                if model.isAnalyzing && model.isRevealed {
                    ProgressView()
                        .controlSize(.small)
                        .help(model.progress?.label ?? "")
                }
                Button("Analyze Again", systemImage: "arrow.clockwise") { model.analyzeAgain() }
                    .help("Read the files on disk again (⌘R)")
                    .disabled(model.isAnalyzing)
                Button("Open Repository", systemImage: "folder") { model.chooseRepository() }
                    .help("Open another repository in this window (⌘O)")
                Button("FAQ", systemImage: "questionmark.circle") { model.showFAQ() }
                    .help("Frequently asked questions")
                    .disabled(!model.isRevealed)
            }
            Button("Support", systemImage: "heart") { ExternalLinks.open(ExternalLinks.support) }
                .help("Codefield is free for personal use. Support its continued development.")
        }
    }
}

extension FocusedValues {
    @Entry var repositoryWindow: RepositoryWindowModel?
}
