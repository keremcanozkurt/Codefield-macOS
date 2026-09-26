import Foundation

nonisolated struct RepositoryListing: Equatable, Sendable {
    struct File: Equatable, Sendable {
        var path: String
        var size: Int
    }

    // Every regular file outside ignored directories, as repository-relative
    // paths with "/" separators.
    var files: [File] = []
    // Every symbolic link found. Links are never followed; the page decides
    // which of them count as skipped source files.
    var symlinks: [String] = []
    // Directories that could not be listed, for example for lack of permission.
    var unreadableDirectories = 0
}

// The directories upstream never looks inside (IGNORED_DIRECTORIES in
// lib/source-files.ts). The page applies upstream's own rule to every path it
// receives as well, so this list only saves the walk from entering them;
// Web/src/ignored-directories.test.ts keeps the two lists equal.
nonisolated enum IgnoredDirectories {
    static let names: Set<String> = [
        ".git", ".hg", ".svn",
        "node_modules", "bower_components", "dist", "build", "out", "coverage",
        ".next", ".nuxt", ".svelte-kit", ".output", ".turbo", ".vercel",
        "vendor",
        ".venv", "venv", "__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".tox", ".eggs", "site-packages",
        "target",
        ".gradle",
        "obj",
        ".dart_tool",
        "_build", "deps",
        ".build", "Pods", "Carthage", "DerivedData",
    ]

    static func contains(_ name: String) -> Bool {
        names.contains(name) || name.hasSuffix(".egg-info")
    }
}

// Lists a directory tree the way upstream's lib/local/walk.ts does: symbolic
// links are recorded but never followed, so the listing can neither leave the
// root nor loop, and each directory is entered once even if a mount makes it
// contain itself. Only names and sizes are read; file contents are read later,
// and only for the files the page selects.
nonisolated enum RepositoryWalker {
    @concurrent
    static func list(
        root: String,
        onProgress: @escaping @MainActor @Sendable (Int) -> Void = { _ in }
    ) async throws -> RepositoryListing {
        var listing = RepositoryListing()
        var visited = Set<DirectoryIdentity>()
        var stack: [(absolute: String, relative: String)] = [(root, "")]
        var reported = 0
        let manager = FileManager()

        while let directory = stack.popLast() {
            try Task.checkCancellation()

            guard let status = FileStatus.of(directory.absolute), status.type == .directory else {
                listing.unreadableDirectories += 1
                continue
            }
            guard visited.insert(DirectoryIdentity(device: status.device, inode: status.inode)).inserted else { continue }

            let names: [String]
            do {
                names = try manager.contentsOfDirectory(atPath: directory.absolute)
            } catch {
                listing.unreadableDirectories += 1
                continue
            }

            for name in names {
                let relative = directory.relative.isEmpty ? name : directory.relative + "/" + name
                let absolute = directory.absolute + "/" + name
                // Removed since the directory was listed.
                guard let entry = FileStatus.of(absolute) else { continue }

                switch entry.type {
                case .directory:
                    if !IgnoredDirectories.contains(name) { stack.append((absolute, relative)) }
                case .symbolicLink:
                    listing.symlinks.append(relative)
                case .regular:
                    listing.files.append(.init(path: relative, size: entry.size))
                case .other:
                    // Sockets, FIFOs and devices: reading a FIFO would block.
                    break
                }
            }

            if listing.files.count - reported >= 500 {
                reported = listing.files.count
                await onProgress(reported)
            }
        }

        // UTF-16 code-unit order, as the page compares paths.
        listing.files.sort { $0.path.utf16.lexicographicallyPrecedes($1.path.utf16) }
        listing.symlinks.sort { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        await onProgress(listing.files.count)
        return listing
    }

    private struct DirectoryIdentity: Hashable {
        var device: Int32
        var inode: UInt64
    }
}
