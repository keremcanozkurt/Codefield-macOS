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
        case .focusSearch:
            return nil
        }
    }
}

// Stands in for the clone helper: "clones" by creating the folder with one
// source file, or fails the way it is told to.
@MainActor
private final class FakeCloner: RepositoryCloner {
    var failure: GitCloneFailure?
    private(set) var requests: [(remote: String, parentPath: String, name: String)] = []

    func clone(remote: String, parentPath: String, directoryName: String) async -> CloneOutcome {
        requests.append((remote, parentPath, directoryName))
        if let failure { return CloneOutcome(failure: failure, detail: "fatal: \(failure.rawValue)") }
        let root = parentPath + "/" + directoryName
        try? FileManager.default.createDirectory(atPath: root + "/src", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root + "/src/main.ts", contents: Data("export {};\n".utf8))
        return .success
    }

    func cancel() {}
}

private let plainBookmarks = Bookmarks(make: { try $0.bookmarkData() }, resolve: { data in
    var isStale = false
    return (try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale), isStale)
})

@MainActor
struct RepositoryWindowModelTests {
    private func model(_ page: FakePage, cloner: FakeCloner? = nil) -> RepositoryWindowModel {
        let defaults = UserDefaults(suiteName: "codefield-tests-\(UUID().uuidString)")!
        return RepositoryWindowModel(
            recents: RecentRepositoryStore(defaults: defaults, key: "recents", bookmarks: plainBookmarks),
            cloneParent: CloneParentFolder(defaults: defaults, key: "parent", bookmarks: plainBookmarks),
            cloner: cloner ?? FakeCloner(),
            makePage: { page }
        )
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

        #expect(window.openDropped([folder.url.appending(path: "a.ts")]) == .refused("Drop a folder, not a file."))
        #expect(window.openDropped([folder.url.appending(path: "b"), folder.url]) == .refused("Drop one folder at a time."))
        #expect(window.openDropped([folder.url.appending(path: "b"), folder.url.appending(path: "a.ts")]) != .opened)
        #expect(window.openDropped([folder.url.appending(path: "missing")]) == .refused("That folder could not be found."))
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

    @Test func clonesThenOpensTheCloneAndRemembersIt() async throws {
        let folder = try TemporaryFolder()
        let page = FakePage()
        let cloner = FakeCloner()
        let window = model(page, cloner: cloner)

        let outcome = await window.clone(remote: "git@example.com:team/project.git", parent: folder.url, name: "project")
        await settle(window)

        #expect(outcome == .success)
        #expect(cloner.requests.count == 1)
        #expect(cloner.requests.first?.parentPath == folder.path)
        #expect(window.repository?.path == folder.path + "/project")
        #expect(window.recents.items.first?.name == "project")
        #expect(window.cloneParent.url?.lastPathComponent == folder.url.lastPathComponent)
        #expect(page.sourcePaths == ["src/main.ts"])
    }

    @Test func aFailedCloneOpensNothing() async throws {
        let folder = try TemporaryFolder()
        let cloner = FakeCloner()
        cloner.failure = .hostVerification
        let window = model(FakePage(), cloner: cloner)

        let outcome = await window.clone(remote: "git@example.com:team/project.git", parent: folder.url, name: "project")

        #expect(outcome.failure == .hostVerification)
        #expect(window.repository == nil)
        #expect(window.recents.items.isEmpty)
    }

    @Test func refusesAnExistingDestinationWithoutRunningGit() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["project/mine.txt": "keep"])
        let cloner = FakeCloner()
        let window = model(FakePage(), cloner: cloner)

        let outcome = await window.clone(remote: "git@example.com:team/project.git", parent: folder.url, name: "project")

        #expect(outcome.failure == .destinationExists)
        #expect(cloner.requests.isEmpty)
        #expect(try String(contentsOfFile: folder.path + "/project/mine.txt", encoding: .utf8) == "keep")
    }

    @Test func cloneSheetNamesTheFolderAndForgetsOldFailuresOnEdit() {
        let request = CloneRequest(parent: URL(filePath: "/tmp", directoryHint: .isDirectory))
        request.remote = "https://example.com/team/app.git"
        #expect(request.name == "app")
        #expect(request.canClone)

        request.state = .failed(.network, detail: nil)
        request.remote = "https://example.com/team/tool.git"
        #expect(request.state == .editing)
        #expect(request.name == "tool")

        request.isNameEdited = true
        request.name = "mine"
        request.remote = "ext::sh"
        #expect(request.name == "mine")
        #expect(request.remoteProblem != nil)
        #expect(!request.canClone)
    }

    @Test func windowsKeepTheirOwnRepositoryAndAnalysis() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["one/a.ts": "", "two/b.ts": "", "two/c.ts": ""])
        let firstPage = FakePage()
        let secondPage = FakePage()
        let first = model(firstPage)
        let second = model(secondPage)

        first.open(folder.url.appending(path: "one"))
        second.open(folder.url.appending(path: "two"))
        await settle(first)
        await settle(second)
        first.analyzeAgain()
        await settle(first)

        #expect(first.repository?.name == "one")
        #expect(second.repository?.name == "two")
        #expect(firstPage.sent == ["begin 1", "finish 1", "begin 2", "finish 2"])
        #expect(secondPage.sent == ["begin 1", "finish 1"])
        #expect(second.outcome == .success(files: 2, edges: 0))
    }

    @Test func offersToRemoveARecentRepositoryThatIsGone() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["gone/a.ts": ""])
        let window = model(FakePage())
        window.open(folder.url.appending(path: "gone"))
        await settle(window)
        window.close()
        try FileManager.default.removeItem(atPath: folder.path + "/gone")

        let item = try #require(window.recents.items.first)
        #expect(window.recents.location(of: item) == nil)
        window.openRecent(item)

        #expect(window.unavailableRecent == item)
        #expect(window.repository == nil)
    }

    @Test func theFAQIsAvailableWithoutARepository() throws {
        let window = model(FakePage())
        window.showFAQ()
        #expect(window.isFAQPresented)
        window.showClone()
        #expect(window.isClonePresented)

        let content = try #require(FAQContent.load())
        #expect(content.supportURL == ExternalLinks.support)
        #expect(content.entries.contains { $0.question.contains("Clone Git Repository") })
        #expect(!content.entries.contains { $0.answer.contains("started with") || $0.answer.contains("127.0.0.1") })
    }
}
