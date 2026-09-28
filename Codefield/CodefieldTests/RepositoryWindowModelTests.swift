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
    var onExport: (Result<URL, any Error>) -> Void = { _ in }
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
        case .focusSearch, .fullScreen:
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

// Answers the export folder panel the way it is told to, and counts how
// often it was shown.
@MainActor
private final class FakeFolderPanel {
    var answer: URL?
    private(set) var shown = 0

    func choose(_ window: NSWindow?, _ completion: @escaping (URL?) -> Void) {
        shown += 1
        completion(answer)
    }
}

@MainActor
struct RepositoryWindowModelTests {
    private func model(_ page: FakePage, cloner: FakeCloner? = nil, panel: FakeFolderPanel? = nil) -> RepositoryWindowModel {
        let defaults = UserDefaults(suiteName: "codefield-tests-\(UUID().uuidString)")!
        let panel = panel ?? FakeFolderPanel()
        return RepositoryWindowModel(
            recents: RecentRepositoryStore(defaults: defaults, key: "recents", bookmarks: plainBookmarks),
            cloneParent: CloneParentFolder(defaults: defaults, key: "parent", bookmarks: plainBookmarks),
            cloner: cloner ?? FakeCloner(),
            exportFolder: ExportFolder(defaults: defaults, key: "export", bookmarks: plainBookmarks),
            chooseFolder: panel.choose,
            makePage: { page }
        )
    }

    // A PNG export as WebKit leaves it: alone in a staging folder.
    private func stagedExport(in temporary: TemporaryFolder, name: String = "codefield-demo.png", data: Data = pngHeader(width: 640, height: 480)) throws -> URL {
        let staged = try ExportFile.stagingURL(for: name, in: temporary.url)
        try data.write(to: staged)
        return staged
    }

    private func settleExport(_ model: RepositoryWindowModel) async {
        for _ in 0..<500 where model.exportNotice == nil && model.exportFailure == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
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
        #expect(content.donationURL == ExternalLinks.donation)
        #expect(content.contactURL == ExternalLinks.contact)
        #expect(ExternalLinks.support.absoluteString == "https://codefield.keremcanozkurt.com/support")
        #expect(ExternalLinks.donation.absoluteString == "https://codefield.keremcanozkurt.com/donation")
        #expect(content.entries.contains { $0.question.contains("Clone Git Repository") })
        #expect(!content.entries.contains { $0.answer.contains("started with") || $0.answer.contains("127.0.0.1") })
    }

    @Test func asksForTheExportFolderOnceThenSavesThere() async throws {
        let temporary = try TemporaryFolder()
        let exports = try TemporaryFolder()
        let panel = FakeFolderPanel()
        panel.answer = exports.url
        let window = model(FakePage(), panel: panel)

        let first = try stagedExport(in: temporary)
        window.saveExport(first)
        await settleExport(window)
        let notice = try #require(window.exportNotice)
        #expect(notice.file.lastPathComponent == "codefield-demo.png")
        #expect(notice.folderPath.hasSuffix("/" + exports.url.lastPathComponent))
        #expect(FileManager.default.fileExists(atPath: exports.path + "/codefield-demo.png"))
        #expect(!FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path(percentEncoded: false)))

        window.dismissExportNotice(notice)
        #expect(window.exportNotice == nil)
        window.saveExport(try stagedExport(in: temporary))
        await settleExport(window)

        #expect(panel.shown == 1)
        #expect(window.exportNotice?.file.lastPathComponent == "codefield-demo 2.png")
        #expect(window.exportFailure == nil)
    }

    @Test func aCancelledFolderChoiceSavesNothing() throws {
        let temporary = try TemporaryFolder()
        let panel = FakeFolderPanel()
        let window = model(FakePage(), panel: panel)

        let staged = try stagedExport(in: temporary)
        window.saveExport(staged)

        #expect(panel.shown == 1)
        #expect(window.exportNotice == nil)
        #expect(window.exportFailure == nil)
        #expect(window.exportFolder.url == nil)
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path(percentEncoded: false)))
    }

    @Test func refusesAnExportThatIsNotAPNG() throws {
        let temporary = try TemporaryFolder()
        let exports = try TemporaryFolder()
        let panel = FakeFolderPanel()
        panel.answer = exports.url
        let window = model(FakePage(), panel: panel)

        let staged = try stagedExport(in: temporary, data: Data("#!/bin/sh\n".utf8))
        window.saveExport(staged)

        #expect(panel.shown == 0)
        #expect(window.exportFailure != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: exports.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path(percentEncoded: false)))
    }

    @Test func asksAgainOnceTheExportFolderIsGone() async throws {
        let temporary = try TemporaryFolder()
        let parent = try TemporaryFolder()
        try parent.write(["old/keep.txt": "", "new/keep.txt": ""])
        let panel = FakeFolderPanel()
        let window = model(FakePage(), panel: panel)
        window.exportFolder.remember(parent.url.appending(path: "old"))
        try FileManager.default.removeItem(atPath: parent.path + "/old")
        panel.answer = parent.url.appending(path: "new")

        window.saveExport(try stagedExport(in: temporary))
        await settleExport(window)

        #expect(panel.shown == 1)
        #expect(FileManager.default.fileExists(atPath: parent.path + "/new/codefield-demo.png"))
        #expect(window.exportFolder.url?.lastPathComponent == "new")
    }

    @Test func choosingTheExportFolderFromTheMenuRemembersIt() throws {
        let exports = try TemporaryFolder()
        let panel = FakeFolderPanel()
        let window = model(FakePage(), panel: panel)

        window.chooseExportFolder()
        #expect(window.exportFolder.url == nil)
        panel.answer = exports.url
        window.chooseExportFolder()

        #expect(panel.shown == 2)
        #expect(window.exportFolder.url?.lastPathComponent == exports.url.lastPathComponent)
    }
}

// The first 24 bytes of a PNG: its signature and the start of its IHDR chunk.
func pngHeader(width: UInt32, height: UInt32) -> Data {
    var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
    data.append(contentsOf: Array("IHDR".utf8))
    for value in [width, height] {
        data.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init))
    }
    return data
}
