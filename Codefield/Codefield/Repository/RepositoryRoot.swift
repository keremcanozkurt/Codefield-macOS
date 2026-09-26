import Foundation

nonisolated enum RepositoryRootError: Error, Equatable {
    case notFound
    case notAFolder
    case permissionDenied

    var message: String {
        switch self {
        case .notFound: "The folder could not be found. It may have been moved or deleted."
        case .notAFolder: "Codefield opens folders. Choose the folder that contains the repository."
        case .permissionDenied: "Codefield is not allowed to read this folder."
        }
    }
}

nonisolated enum RepositoryRoot {
    // The real path of the folder, which becomes the only root the analysis
    // reads. A folder that cannot be listed is refused here rather than
    // opening as an empty repository.
    static func resolve(_ url: URL) -> Result<String, RepositoryRootError> {
        guard url.isFileURL else { return .failure(.notFound) }
        guard let real = realPath(url.path(percentEncoded: false)) else {
            return .failure(errno == EACCES || errno == EPERM ? .permissionDenied : .notFound)
        }

        guard let status = FileStatus.follow(real) else { return .failure(.notFound) }
        guard status.type == .directory else { return .failure(.notAFolder) }

        guard let directory = opendir(real) else { return .failure(.permissionDenied) }
        closedir(directory)
        return .success(real)
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

// Keeps a security-scoped URL open for as long as the repository is in use.
// URLs from the open panel or a drop are already accessible for the life of
// the process; those resolved from bookmarks are not until this starts.
nonisolated final class RepositoryAccess: Sendable {
    let url: URL
    private let started: Bool

    init(url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if started { url.stopAccessingSecurityScopedResource() }
    }
}

nonisolated struct OpenedRepository: Sendable {
    // The real path, without a trailing slash.
    let path: String
    let access: RepositoryAccess

    var name: String { (path as NSString).lastPathComponent }
    var url: URL { URL(filePath: path, directoryHint: .isDirectory) }
}
