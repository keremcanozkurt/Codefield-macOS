import Foundation
import Testing
@testable import Codefield

struct BridgeMessageTests {
    @Test func encodesBeginAsPlainValues() throws {
        var listing = RepositoryListing()
        listing.files = [.init(path: "src/a.ts", size: 12)]
        listing.symlinks = ["link.ts"]
        let message = NativeMessage.begin(
            run: 3,
            fresh: true,
            repository: RepositoryIdentity(name: "demo", branch: "main", remote: nil),
            listing: listing
        )

        let payload = message.payload
        #expect(payload["type"] as? String == "analysis.begin")
        #expect(payload["run"] as? Int == 3)
        #expect(payload["fresh"] as? Bool == true)
        let repository = try #require(payload["repository"] as? [String: Any])
        #expect(repository["name"] as? String == "demo")
        #expect(repository["remote"] is NSNull)
        let encodedListing = try #require(payload["listing"] as? [String: Any])
        #expect((encodedListing["files"] as? [[Any]])?.first?.first as? String == "src/a.ts")
        #expect(encodedListing["unreadableDirectories"] as? Int == 0)
        #expect(JSONSerialization.isValidJSONObject(payload))
    }

    @Test func encodesSourcesAndFailures() {
        let sources = NativeMessage.sources(
            run: 1,
            files: [SourceText(path: "a.ts", text: "x")],
            skipped: [SkippedFile(path: "b.ts", reason: .tooLarge)]
        ).payload
        #expect(sources["skipped"] as? [[String]] == [["b.ts", "too_large"]])
        #expect(sources["files"] as? [[String]] == [["a.ts", "x"]])
        #expect(NativeMessage.fail(run: 1, error: .resourcesExceeded).payload["error"] as? String == "resources_exceeded")
        #expect(NativeMessage.focusSearch.payload.count == 1)
    }

    @Test func decodesReplies() {
        #expect(BeginReply(reply: ["read": ["sources": ["a.ts"], "configs": []]]) == .read(sources: ["a.ts"], configs: []))
        #expect(BeginReply(reply: ["outcome": ["status": "empty"]]) == .outcome(.empty))
        #expect(AnalysisOutcome(reply: ["status": "success", "files": 3, "edges": 2.0]) == .success(files: 3, edges: 2))
        #expect(BeginReply(reply: ["read": ["sources": [1], "configs": []]]) == nil)
        #expect(BeginReply(reply: nil) == nil)
        #expect(AnalysisOutcome(reply: ["status": "success", "files": -1, "edges": 0]) == nil)
        #expect(AnalysisOutcome(reply: ["status": "done"]) == nil)
    }

    @Test func acceptsWellFormedPageMessages() {
        #expect(PageMessage(body: ["type": "ready"]) == .ready)
        #expect(PageMessage(body: ["type": "analyzeAgain"]) == .analyzeAgain)
        #expect(PageMessage(body: ["type": "progress", "run": NSNumber(value: 2), "stage": "graph"]) == .progress(run: 2, stage: .graph))
    }

    @Test func rejectsMalformedPageMessages() {
        #expect(PageMessage(body: "ready") == nil)
        #expect(PageMessage(body: [["type": "ready"]]) == nil)
        let rejected: [[String: Any]] = [
            [:],
            ["type": "open", "path": "/etc/passwd"],
            ["type": "ready", "extra": true],
            ["type": "progress", "run": 1, "stage": "unknown"],
            ["type": "progress", "run": 0, "stage": "graph"],
            ["type": "progress", "run": 1.5, "stage": "graph"],
            ["type": "progress", "run": NSNumber(value: true), "stage": "graph"],
            ["type": "progress", "run": "1", "stage": "graph"],
            ["type": "progress", "stage": "graph"],
        ]
        for body in rejected {
            #expect(PageMessage(body: body) == nil)
        }
    }
}

struct WorkspaceResourceTests {
    @Test func servesOnlyTheBuiltFiles() {
        #expect(WorkspaceSchemeHandler.resource(for: URL(string: "codefield://workspace/workspace.html")!)?.name == "workspace.html")
        #expect(WorkspaceSchemeHandler.resource(for: URL(string: "codefield://workspace/analysis-worker.js")!)?.mimeType.hasPrefix("text/javascript") == true)

        let refused = [
            "codefield://workspace/",
            "codefield://workspace/Info.plist",
            "codefield://workspace/../Info.plist",
            "codefield://workspace/%2E%2E/workspace.js",
            "codefield://workspace/sub/workspace.js",
            "codefield://workspace/workspace.js?x=1",
            "codefield://other/workspace.js",
            "https://workspace/workspace.js",
            "file:///etc/passwd",
        ]
        for url in refused {
            #expect(WorkspaceSchemeHandler.resource(for: URL(string: url)!) == nil, "\(url)")
        }
    }

    @Test func theBuiltFilesAreInTheBundle() {
        for name in WorkspaceSchemeHandler.files.keys {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            #expect(Bundle.main.url(forResource: base, withExtension: ext) != nil, "\(name)")
        }
    }

    @Test func opensOnlyTheCodefieldSite() {
        #expect(ExternalLinks.isAllowed(URL(string: "https://codefield.keremcanozkurt.com/support")!))
        #expect(!ExternalLinks.isAllowed(URL(string: "http://codefield.keremcanozkurt.com/support")!))
        #expect(!ExternalLinks.isAllowed(URL(string: "https://example.com/")!))
        #expect(!ExternalLinks.isAllowed(URL(string: "https://codefield.keremcanozkurt.com.example.com/")!))
        #expect(!ExternalLinks.isAllowed(URL(string: "file:///etc/passwd")!))
    }

    @Test func savesOnlyPNGExportsUnderFreeNames() throws {
        #expect(ExportFile.acceptedName("codefield-my-repo.png") == "codefield-my-repo.png")
        #expect(ExportFile.acceptedName("codefield-repo.png.app") == nil)
        #expect(ExportFile.acceptedName("../codefield-repo.png") == nil)
        #expect(ExportFile.acceptedName("payload.command") == nil)

        let folder = try TemporaryFolder()
        #expect(ExportFile.availableURL(for: "codefield-x.png", in: folder.url).lastPathComponent == "codefield-x.png")
        try folder.write(["codefield-x.png": "", "codefield-x 2.png": ""])
        #expect(ExportFile.availableURL(for: "codefield-x.png", in: folder.url).lastPathComponent == "codefield-x 3.png")
    }

    @Test func movesAStagedExportWithoutReplacingEarlierOnes() throws {
        let temporary = try TemporaryFolder()
        let downloads = try TemporaryFolder()
        try downloads.write(["codefield-x.png": "earlier"])

        let staged = try ExportFile.stagingURL(for: "codefield-x.png", in: temporary.url)
        try Data("image".utf8).write(to: staged)
        let saved = try ExportFile.move(staged, into: downloads.url)

        #expect(saved.lastPathComponent == "codefield-x 2.png")
        #expect(try String(contentsOf: saved, encoding: .utf8) == "image")
        #expect(try String(contentsOfFile: downloads.path + "/codefield-x.png", encoding: .utf8) == "earlier")
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path(percentEncoded: false)))
    }
}
