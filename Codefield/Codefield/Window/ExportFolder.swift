import AppKit

// The folder Export PNG saves to. It is asked for the first time an export
// is saved and kept as a security-scoped bookmark, so later exports go
// straight there. File > Choose Export Folder changes it.
final class ExportFolder {
    private let defaults: UserDefaults
    private let key: String
    private let bookmarks: Bookmarks

    init(defaults: UserDefaults = .standard, key: String = "ExportFolder", bookmarks: Bookmarks = .securityScopedReadWrite) {
        self.defaults = defaults
        self.key = key
        self.bookmarks = bookmarks
    }

    // The chosen folder, with its security scope not yet started. Nil until
    // one is chosen, and again once it can no longer be found.
    var url: URL? {
        guard let data = defaults.data(forKey: key), let resolved = try? bookmarks.resolve(data) else { return nil }
        let access = RepositoryAccess(url: resolved.url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: access.url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        if resolved.isStale, let renewed = try? bookmarks.make(resolved.url) { defaults.set(renewed, forKey: key) }
        return resolved.url
    }

    func remember(_ url: URL) {
        if let data = try? bookmarks.make(url) { defaults.set(data, forKey: key) }
    }

    // An open panel for choosing the folder, as a sheet on `window` when
    // there is one. It starts in Downloads.
    static func choose(for window: NSWindow?, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for exported PNGs. Later exports are saved there too."
        // The sandbox's Downloads is a link in the app's container to the
        // real one.
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
        if let window {
            panel.beginSheetModal(for: window) { response in
                completion(response == .OK ? panel.url : nil)
            }
        } else {
            completion(panel.runModal() == .OK ? panel.url : nil)
        }
    }
}

// Shown for a few seconds after an export is saved.
struct ExportNotice: Equatable, Identifiable {
    let id = UUID()
    let file: URL
    let folder: URL

    var fileName: String { file.lastPathComponent }

    var folderPath: String {
        RecentRepositoryStore.abbreviatingHome(RecentRepositoryStore.standardPath(folder))
    }
}
