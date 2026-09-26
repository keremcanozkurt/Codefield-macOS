//
//  CodefieldApp.swift
//  Codefield
//
//  Created by Kerem Can Özkurt on 26.09.2026.
//

import SwiftUI

@main
struct CodefieldApp: App {
    static let windowID = "repository"

    var body: some Scene {
        WindowGroup(id: Self.windowID) {
            ContentView()
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { AppCommands(recents: .shared) }
    }
}
