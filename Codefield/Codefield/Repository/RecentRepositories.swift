import Foundation
import Observation

nonisolated struct RecentRepository: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    // A security-scoped, read-only bookmark. File contents and credentials
    // are never stored.
    var bookmark: Data
    var lastOpened: Date
}

nonisolated struct Bookmarks: Sendable {
    var make: @Sendable (URL) throws -> Data
    var resolve: @Sendable (Data) throws -> (url: URL, isStale: Bool)

    static let securityScoped = Bookmarks(
        make: { url in
            try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        resolve: { data in
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        }
    )
}

@Observable
final class RecentRepositoryStore {
    static let shared: RecentRepositoryStore = {
        #if DEBUG
        if UITestFixture.isActive {
            UserDefaults.standard.removeObject(forKey: "UITestRecentRepositories")
            return RecentRepositoryStore(key: "UITestRecentRepositories")
        }
        #endif
        return RecentRepositoryStore()
    }()
    static let limit = 10

    private(set) var items: [RecentRepository]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let bookmarks: Bookmarks

    init(defaults: UserDefaults = .standard, key: String = "RecentRepositories", bookmarks: Bookmarks = .securityScoped) {
        self.defaults = defaults
        self.key = key
        self.bookmarks = bookmarks
        items = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RecentRepository].self, from: $0) } ?? []
    }

    // Moves the folder to the top of the list, replacing an older entry for
    // the same folder.
    func noteOpened(_ url: URL, now: Date = .now) {
        guard let bookmark = try? bookmarks.make(url) else { return }
        let path = Self.standardPath(url)
        var updated = items.filter { item in
            (try? bookmarks.resolve(item.bookmark)).map { Self.standardPath($0.url) != path } ?? true
        }
        updated.insert(RecentRepository(id: UUID(), name: url.lastPathComponent, bookmark: bookmark, lastOpened: now), at: 0)
        items = Array(updated.prefix(Self.limit))
        save()
    }

    // The folder the bookmark points to, with its security scope not yet
    // started. A stale bookmark is renewed.
    func resolve(_ item: RecentRepository) -> URL? {
        guard let resolved = try? bookmarks.resolve(item.bookmark) else { return nil }
        if resolved.isStale, let renewed = try? bookmarks.make(resolved.url),
           let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].bookmark = renewed
            save()
        }
        return resolved.url
    }

    // A security-scoped URL for a folder the app can reach right now only
    // through another grant, such as the parent folder a clone went into.
    func bookmarkedURL(for url: URL) -> URL? {
        guard let data = try? bookmarks.make(url) else { return nil }
        return try? bookmarks.resolve(data).url
    }

    // The folder the repository is in, for display; nil when the repository
    // can no longer be found.
    func location(of item: RecentRepository) -> String? {
        guard let url = try? bookmarks.resolve(item.bookmark).url,
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        return Self.abbreviatingHome(Self.standardPath(url.deletingLastPathComponent()))
    }

    func remove(_ item: RecentRepository) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }

    nonisolated static func standardPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
    }

    // The sandbox points HOME at the app's container, so the user's real home
    // comes from the password database.
    nonisolated static func abbreviatingHome(_ path: String) -> String {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir.map({ String(cString: $0) }), !home.isEmpty else {
            return path
        }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

private extension String {
    nonisolated func trimmingSuffix(_ suffix: String) -> String {
        count > suffix.count && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
