import Foundation
import Testing
@testable import Codefield

struct RepositoryRootTests {
    @Test func resolvesAFolderToItsRealPath() throws {
        let folder = try TemporaryFolder()
        try folder.write(["repo/src/a.ts": ""])
        try folder.link("alias", to: folder.path + "/repo")

        #expect(RepositoryRoot.resolve(URL(filePath: folder.path + "/repo")) == .success(folder.path + "/repo"))
        #expect(RepositoryRoot.resolve(URL(filePath: folder.path + "/alias")) == .success(folder.path + "/repo"))
        #expect(RepositoryRoot.resolve(URL(filePath: folder.path + "/repo/src/../")) == .success(folder.path + "/repo"))
    }

    @Test func refusesFilesAndMissingFolders() throws {
        let folder = try TemporaryFolder()
        try folder.write(["file.ts": ""])

        #expect(RepositoryRoot.resolve(URL(filePath: folder.path + "/file.ts")) == .failure(.notAFolder))
        #expect(RepositoryRoot.resolve(URL(filePath: folder.path + "/missing")) == .failure(.notFound))
        #expect(RepositoryRoot.resolve(URL(string: "https://example.com/repo")!) == .failure(.notFound))
    }

    @Test func refusesAFolderThatCannotBeListed() throws {
        let folder = try TemporaryFolder()
        try folder.write(["locked/a.ts": ""])
        let locked = folder.path + "/locked"
        chmod(locked, 0o000)
        defer { chmod(locked, 0o755) }

        #expect(RepositoryRoot.resolve(URL(filePath: locked)) == .failure(.permissionDenied))
    }
}

@MainActor
struct RecentRepositoryStoreTests {
    // Plain bookmarks: the security scope needs the sandbox, which the tests
    // do not depend on.
    private let bookmarks = Bookmarks(
        make: { try $0.bookmarkData() },
        resolve: { data in
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        }
    )

    private func store(_ defaults: UserDefaults) -> RecentRepositoryStore {
        RecentRepositoryStore(defaults: defaults, key: "recents", bookmarks: bookmarks)
    }

    private func defaults() -> UserDefaults {
        let name = "codefield-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func keepsTheMostRecentFirstWithoutDuplicates() throws {
        let folder = try TemporaryFolder()
        try folder.write(["a/x.ts": "", "b/x.ts": ""])
        let recents = store(defaults())

        recents.noteOpened(folder.url.appending(path: "a"), now: Date(timeIntervalSince1970: 1))
        recents.noteOpened(folder.url.appending(path: "b"), now: Date(timeIntervalSince1970: 2))
        recents.noteOpened(folder.url.appending(path: "a"), now: Date(timeIntervalSince1970: 3))

        #expect(recents.items.map(\.name) == ["a", "b"])
        #expect(recents.items.first?.lastOpened == Date(timeIntervalSince1970: 3))
    }

    @Test func persistsOnlyNamesBookmarksAndDates() throws {
        let folder = try TemporaryFolder()
        try folder.write(["repo/x.ts": "secret source"])
        let storage = defaults()
        store(storage).noteOpened(folder.url.appending(path: "repo"))

        let reloaded = store(storage)
        #expect(reloaded.items.map(\.name) == ["repo"])
        #expect(reloaded.resolve(reloaded.items[0])?.lastPathComponent == "repo")

        let stored = try #require(storage.data(forKey: "recents"))
        let object = try #require(JSONSerialization.jsonObject(with: stored) as? [[String: Any]])
        #expect(Set(object[0].keys) == ["id", "name", "bookmark", "lastOpened"])
        #expect(!String(decoding: stored, as: UTF8.self).contains("secret source"))
    }

    @Test func keepsAtMostTheLimit() throws {
        let folder = try TemporaryFolder()
        let recents = store(defaults())
        for index in 0..<(RecentRepositoryStore.limit + 3) {
            try folder.write(["r\(index)/x.ts": ""])
            recents.noteOpened(folder.url.appending(path: "r\(index)"))
        }
        #expect(recents.items.count == RecentRepositoryStore.limit)
        #expect(recents.items.first?.name == "r\(RecentRepositoryStore.limit + 2)")
    }

    @Test func removesOneOrAll() throws {
        let folder = try TemporaryFolder()
        try folder.write(["a/x.ts": "", "b/x.ts": ""])
        let storage = defaults()
        let recents = store(storage)
        recents.noteOpened(folder.url.appending(path: "a"))
        recents.noteOpened(folder.url.appending(path: "b"))

        recents.remove(recents.items[0])
        #expect(store(storage).items.map(\.name) == ["a"])
        recents.clear()
        #expect(store(storage).items.isEmpty)
    }

    @Test func abbreviatesTheHomeFolder() {
        let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        #expect(RecentRepositoryStore.abbreviatingHome(home + "/Developer/app") == "~/Developer/app")
        #expect(RecentRepositoryStore.abbreviatingHome(home + "other") == home + "other")
        #expect(RecentRepositoryStore.abbreviatingHome("/opt/app") == "/opt/app")
    }
}

struct GitMetadataTests {
    @Test func showsHostAndPathForRemotesOfAnyHost() {
        #expect(GitMetadata.displayRemote("git@github.com:user/project.git") == "github.com/user/project")
        #expect(GitMetadata.displayRemote("git@gitlab.com:group/sub/project.git") == "gitlab.com/group/sub/project")
        #expect(GitMetadata.displayRemote("ssh://git@bitbucket.org:2222/team/project.git") == "bitbucket.org/team/project")
        #expect(GitMetadata.displayRemote("https://codeberg.org/user/project") == "codeberg.org/user/project")
    }

    @Test func dropsCredentials() {
        #expect(GitMetadata.displayRemote("https://oauth2:glpat-secret@gitlab.com/g/p.git") == "gitlab.com/g/p")
        #expect(GitMetadata.displayRemote("https://x-access-token:ghs_secret@github.com/o/r") == "github.com/o/r")
    }

    @Test func hidesLocalPaths() {
        #expect(GitMetadata.displayRemote("/srv/git/project.git") == nil)
        #expect(GitMetadata.displayRemote("../project") == nil)
        #expect(GitMetadata.displayRemote("file:///srv/git/project.git") == nil)
        #expect(GitMetadata.displayRemote("C:\\repos\\project") == nil)
    }

    @Test func readsTheOriginAndBranch() {
        let config = "[core]\r\n\tbare = false\r\n[remote \"upstream\"]\r\n\turl = git@example.com:up/p.git\r\n[remote \"origin\"]\r\n\turl = git@example.com:me/p.git\r\n"
        #expect(GitMetadata.originURL(config: config) == "git@example.com:me/p.git")
        #expect(GitMetadata.originURL(config: "[core]\n\tbare = false\n") == nil)
        #expect(GitMetadata.branch(fromHead: "ref: refs/heads/main\n") == "main")
        #expect(GitMetadata.branch(fromHead: "4b825dc642cb6eb9a060e54bf8d69288fbee4904\n") == nil)
    }

    @Test func findsTheRepositoryFromASubdirectory() throws {
        let folder = try TemporaryFolder()
        try folder.write([".git/HEAD": "ref: refs/heads/dev\n", ".git/config": "", "src/a.ts": ""])
        #expect(GitMetadata.read(root: folder.path + "/src") == GitMetadata(branch: "dev", remote: nil))
    }

    @Test func followsAWorktreePointer() throws {
        let folder = try TemporaryFolder()
        try folder.write([
            "main/.git/config": "[remote \"origin\"]\n\turl = git@example.com:team/app.git\n",
            "main/.git/worktrees/wt/HEAD": "ref: refs/heads/topic\n",
            "main/.git/worktrees/wt/commondir": "../..\n",
            "wt/.git": "gitdir: \(folder.path)/main/.git/worktrees/wt\n",
        ])
        #expect(GitMetadata.read(root: folder.path + "/wt") == GitMetadata(branch: "topic", remote: "example.com/team/app"))
    }
}
