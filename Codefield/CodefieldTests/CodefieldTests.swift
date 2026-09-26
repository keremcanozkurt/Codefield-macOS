//
//  CodefieldTests.swift
//  CodefieldTests
//
//  Created by Kerem Can Özkurt on 26.09.2026.
//

import Foundation
@testable import Codefield

// A folder under the temporary directory, resolved to its real path the way
// the app resolves a repository root.
final class TemporaryFolder {
    let path: String

    init() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "codefield-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = RepositoryRoot.realPath(url.path(percentEncoded: false))!
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    var url: URL { URL(filePath: path, directoryHint: .isDirectory) }

    func write(_ files: [String: String]) throws {
        for (relative, content) in files {
            try write(relative, data: Data(content.utf8))
        }
    }

    func write(_ relative: String, data: Data) throws {
        let url = URL(filePath: path + "/" + relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func link(_ relative: String, to destination: String) throws {
        let url = URL(filePath: path + "/" + relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path(percentEncoded: false), withDestinationPath: destination)
    }
}
