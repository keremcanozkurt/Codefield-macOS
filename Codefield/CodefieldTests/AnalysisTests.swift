import Foundation
import Testing
@testable import Codefield

struct RepositoryWalkerTests {
    @Test func listsFilesWithSizesAndSkipsIgnoredDirectories() async throws {
        let folder = try TemporaryFolder()
        try folder.write([
            "src/index.ts": "12345",
            "src/lib/util.ts": "",
            "README.md": "# demo",
            "bin/tool.rb": "",
            "node_modules/pkg/index.js": "",
            ".git/HEAD": "ref: refs/heads/main",
            "demo.egg-info/PKG-INFO": "",
            "nested/build/out.js": "",
        ])

        let listing = try await RepositoryWalker.list(root: folder.path)

        #expect(listing.files == [
            .init(path: "README.md", size: 6),
            .init(path: "bin/tool.rb", size: 0),
            .init(path: "src/index.ts", size: 5),
            .init(path: "src/lib/util.ts", size: 0),
        ])
        #expect(listing.symlinks.isEmpty)
        #expect(listing.unreadableDirectories == 0)
    }

    @Test func recordsSymbolicLinksWithoutFollowingThem() async throws {
        let folder = try TemporaryFolder()
        let outside = try TemporaryFolder()
        try outside.write(["secret.ts": "export const key = 1;"])
        try folder.write(["src/a.ts": ""])
        try folder.link("src/link.ts", to: folder.path + "/src/a.ts")
        try folder.link("escape", to: outside.path)
        try folder.link("loop", to: folder.path)

        let listing = try await RepositoryWalker.list(root: folder.path)

        #expect(listing.files.map(\.path) == ["src/a.ts"])
        #expect(listing.symlinks == ["escape", "loop", "src/link.ts"])
    }

    @Test func countsDirectoriesItCannotList() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["open/a.ts": "", "locked/b.ts": ""])
        chmod(folder.path + "/locked", 0o000)
        defer { chmod(folder.path + "/locked", 0o755) }

        let listing = try await RepositoryWalker.list(root: folder.path)

        #expect(listing.files.map(\.path) == ["open/a.ts"])
        #expect(listing.unreadableDirectories == 1)
    }

    @Test func keepsNamesAsTheyAre() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["with space/ünïcode.ts": "", "back\\slash.ts": ""])

        let listing = try await RepositoryWalker.list(root: folder.path)

        #expect(Set(listing.files.map(\.path)) == ["with space/ünïcode.ts", "back\\slash.ts"])
    }

    @Test func stopsWhenCancelled() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["a.ts": ""])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RepositoryWalker.list(root: folder.path)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

struct SourceReaderTests {
    @Test func readsUTF8AndDropsAByteOrderMark() throws {
        let folder = try TemporaryFolder()
        try folder.write(["a.ts": "export const a = \"é\";\n", "empty.ts": ""])
        try folder.write("bom.ts", data: Data([0xEF, 0xBB, 0xBF] + Array("x".utf8)))
        let reader = SourceReader(root: folder.path)

        #expect(reader.read("a.ts", maxBytes: 1024) == .text("export const a = \"é\";\n"))
        #expect(reader.read("empty.ts", maxBytes: 1024) == .text(""))
        #expect(reader.read("bom.ts", maxBytes: 1024) == .text("x"))
    }

    @Test func skipsWhatIsNotSafeToRead() throws {
        let folder = try TemporaryFolder()
        let outside = try TemporaryFolder()
        try outside.write(["secret.ts": "key"])
        try folder.write(["large.ts": String(repeating: "x", count: 11), "dir/a.ts": ""])
        try folder.write("latin1.ts", data: Data([0x63, 0xE9]))
        try folder.link("link.ts", to: folder.path + "/large.ts")
        try folder.link("escape", to: outside.path)
        mkfifo(folder.path + "/pipe.ts", 0o644)
        let reader = SourceReader(root: folder.path)

        #expect(reader.read("large.ts", maxBytes: 10) == .skipped(.tooLarge))
        #expect(reader.read("latin1.ts", maxBytes: 10) == .skipped(.notUTF8))
        #expect(reader.read("link.ts", maxBytes: 100) == .skipped(.symlink))
        #expect(reader.read("escape/secret.ts", maxBytes: 100) == .skipped(.symlink))
        #expect(reader.read("pipe.ts", maxBytes: 100) == .skipped(.unreadable))
        #expect(reader.read("dir", maxBytes: 100) == .skipped(.unreadable))
        #expect(reader.read("missing.ts", maxBytes: 100) == .skipped(.unreadable))
    }

    @Test func readsInBatchesAndStopsAtTheMemoryLimit() async throws {
        let folder = try TemporaryFolder()
        try folder.write(["a.ts": "aaaa", "b.ts": "bbbb", "c.ts": "cccc"])
        try folder.write("bad.ts", data: Data([0xFF]))
        let reader = SourceReader(root: folder.path)
        let paths = ["a.ts", "bad.ts", "b.ts", "c.ts"]

        let all = try await SourceLoader.readBatch(reader, paths: paths, from: 0, textUnits: 0)
        #expect(all.files.map(\.path) == ["a.ts", "b.ts", "c.ts"])
        #expect(all.skipped == [SkippedFile(path: "bad.ts", reason: .notUTF8)])
        #expect(all.next == 4 && all.textUnits == 12 && !all.exceeded)

        let limited = try await SourceLoader.readBatch(reader, paths: paths, from: 0, textUnits: 0, limit: 6)
        #expect(limited.exceeded)
        #expect(limited.next == 3)

        let configs = await SourceLoader.readConfigs(reader, paths: ["a.ts", "bad.ts", "missing.json"])
        #expect(configs == [SourceText(path: "a.ts", text: "aaaa")])
    }

    // No limit on the number of files: everything is listed and read, in
    // batches small enough that neither side holds a second full copy.
    @Test func readsLargeRepositoriesInBoundedBatches() async throws {
        let folder = try TemporaryFolder()
        let content = Data("export const value = 1;\n".utf8)
        for directory in 0..<60 {
            let path = folder.path + "/d\(directory)"
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            for file in 0..<200 {
                FileManager.default.createFile(atPath: path + "/f\(file).ts", contents: content)
            }
        }

        let listing = try await RepositoryWalker.list(root: folder.path)
        #expect(listing.files.count == 12_000)

        let reader = SourceReader(root: folder.path)
        let paths = listing.files.map(\.path)
        var next = 0
        var units = 0
        var read = 0
        var batches = 0
        while next < paths.count {
            let batch = try await SourceLoader.readBatch(reader, paths: paths, from: next, textUnits: units)
            #expect(batch.files.count + batch.skipped.count <= SourceLoader.maxBatchFiles)
            next = batch.next
            units = batch.textUnits
            read += batch.files.count
            batches += 1
        }
        #expect(read == 12_000)
        #expect(batches == 30)
    }
}
