import AppKit
import Foundation
import Testing
@testable import Codefield

// Answers the app's messages the way the workspace page does, from a
// scripted plan, and records what it was sent.
@MainActor
private final class FakePage: WorkspacePage {
    let view = NSView()
    var isReady = true
    var onMessage: (PageMessage) -> Void = { _ in }
    var onPageReset: () -> Void = {}
    var requestExtra: [String] = []
    private(set) var sent: [String] = []
    private(set) var sourcePaths: [String] = []
    private(set) var fresh: [Bool] = []

    func waitUntilReady() async {}
    func focus() {}
    func tearDown() {}

    func send(_ message: NativeMessage) async throws -> Any? {
        switch message {
        case let .begin(run, isFresh, _, listing):
            sent.append("begin \(run)")
            fresh.append(isFresh)
            let sources = listing.files.map(\.path).filter { $0.hasSuffix(".ts") } + requestExtra
            if sources.isEmpty { return ["outcome": ["status": "unsupported"]] }
            return ["read": ["sources": sources, "configs": [String]()]]
        case let .sources(_, files, skipped):
            sourcePaths += files.map(\.path) + skipped.map(\.path)
            return nil
        case let .finish(run):
            sent.append("finish \(run)")
            return ["status": "success", "files": sourcePaths.count, "edges": 0]
        case let .fail(run, error):
            sent.append("fail \(run) \(error.rawValue)")
            return ["status": "error"]
        case let .cancel(run):
            sent.append("cancel \(run)")
            return ["status": "cancelled"]
        case .configs:
            return nil
        case .showFAQ, .focusSearch:
            return nil
        }
    }
}

@MainActor
struct RepositoryWindowModelTests {
    private func model(_ page: FakePage) -> RepositoryWindowModel {
        let name = "codefield-tests-\(UUID().uuidString)"
        let recents = RecentRepositoryStore(
            defaults: UserDefaults(suiteName: name)!,
            key: "recents",
            bookmarks: Bookmarks(make: { try $0.bookmarkData() }, resolve: { data in
                var isStale = false
                return (try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale), isStale)
            })
        )
        return RepositoryWindowModel(recents: recents, makePage: { page })
    }

    private func settle(_ model: RepositoryWindowModel) async {
        for _ in 0..<500 where model.isAnalyzing {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func opensAFolderAndAnalyzesIt() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["repo/src/a.ts": "import './b'", "repo/src/b.ts": "", "repo/README.md": ""])
        let page = FakePage()
        let window = model(page)

        window.open(folder.url.appending(path: "repo"))
        #expect(window.repository?.path == folder.path + "/repo")
        await settle(window)

        #expect(window.outcome == .success(files: 2, edges: 0))
        #expect(window.isRevealed)
        #expect(page.sent == ["begin 1", "finish 1"])
        #expect(page.sourcePaths == ["src/a.ts", "src/b.ts"])
        #expect(window.recents.items.map(\.name) == ["repo"])
    }

    @Test func refusesFilesAndSeveralDroppedItems() throws {
        let folder = try TemporaryFolder()
        try folder.write(["a.ts": "", "b/c.ts": ""])
        let window = model(FakePage())

        window.open(folder.url.appending(path: "a.ts"))
        #expect(window.repository == nil)
        #expect(window.alert != nil)

        #expect(!window.openDropped([folder.url.appending(path: "a.ts")]))
        #expect(!window.openDropped([folder.url.appending(path: "b"), folder.url]))
        #expect(window.repository == nil)
    }

    @Test func analyzeAgainReadsTheCurrentFilesAndKeepsTheSession() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["src/a.ts": ""])
        let page = FakePage()
        let window = model(page)
        window.open(folder.url)
        await settle(window)

        try folder.write(["src/new.ts": ""])
        try FileManager.default.removeItem(atPath: folder.path + "/src/a.ts")
        window.analyzeAgain()
        await settle(window)

        #expect(page.fresh == [true, false])
        #expect(page.sourcePaths == ["src/a.ts", "src/new.ts"])
        #expect(window.outcome == .success(files: 2, edges: 0))
    }

    @Test func openingAnotherFolderCancelsAndStartsAFreshSession() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["one/a.ts": "", "two/b.ts": ""])
        let page = FakePage()
        let window = model(page)

        window.open(folder.url.appending(path: "one"))
        window.open(folder.url.appending(path: "two"))
        await settle(window)

        #expect(window.repository?.name == "two")
        #expect(page.fresh.last == true)
        #expect(page.sent.contains("cancel 1"))
        #expect(page.sent.last == "finish 2")
    }

    @Test func refusesToReadFilesOutsideTheListing() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["repo/a.ts": "", "outside.ts": "secret"])
        let page = FakePage()
        page.requestExtra = ["../outside.ts"]
        let window = model(page)

        window.open(folder.url.appending(path: "repo"))
        await settle(window)

        #expect(page.sent == ["begin 1", "fail 1 failed"])
        #expect(page.sourcePaths.isEmpty)
        #expect(window.outcome == .error)
    }

    @Test func reportsAnUnsupportedFolderWithoutReadingIt() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["README.md": "", "notes.txt": ""])
        let page = FakePage()
        let window = model(page)

        window.open(folder.url)
        await settle(window)

        #expect(window.outcome == .unsupported)
        #expect(page.sent == ["begin 1"])
    }
}
