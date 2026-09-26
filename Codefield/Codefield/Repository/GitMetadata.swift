import Foundation

// A port of upstream lib/local/git-metadata.ts. The branch and origin are read
// from the files in .git rather than by running git: a repository's own
// config can make some git commands run programs it names, and Codefield
// never runs anything from the repository it analyzes.
nonisolated struct GitMetadata: Equatable, Sendable {
    // Nil for a detached HEAD.
    var branch: String?
    // Host and path of origin, such as "github.com/owner/repo", without any
    // user name, password or token the URL may contain.
    var remote: String?

    // The folder may be a subdirectory of a repository, so parents are
    // searched too. In the sandbox, parents outside the opened folder are not
    // readable, and the folder then shows no Git details.
    static func read(root: String) -> GitMetadata? {
        guard let gitDirectory = findGitDirectory(from: root) else { return nil }

        let branch = readSmallFile(gitDirectory + "/HEAD").flatMap(Self.branch(fromHead:))
        // Linked worktrees keep their config in the main repository's directory.
        let configDirectory = readSmallFile(gitDirectory + "/commondir")
            .map { resolvePath($0.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: gitDirectory) } ?? gitDirectory
        let remote = readSmallFile(configDirectory + "/config").flatMap(originURL(config:)).flatMap(displayRemote)
        return GitMetadata(branch: branch, remote: remote)
    }

    static func branch(fromHead head: String) -> String? {
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = line.wholeMatch(of: /ref:\s*refs\/heads\/(.+)/) else { return nil }
        return String(match.1)
    }

    // The url of [remote "origin"]. Only the plain form Git writes itself is
    // understood; anything else counts as no origin.
    static func originURL(config: String) -> String? {
        var inOrigin = false
        for raw in config.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line.wholeMatch(of: /\[remote\s+"origin"\]/) != nil
                continue
            }
            guard inOrigin, let match = line.wholeMatch(of: /url\s*=\s*(.+)/) else { continue }
            let value = match.1.trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                return String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }

    // "host/path" for a remote URL, dropping credentials, ports, query strings
    // and a trailing ".git". Nil for local paths and file URLs, which would
    // only show the user's own directory layout.
    static func displayRemote(_ url: String) -> String? {
        if let scp = url.wholeMatch(of: /(?:[^@\/\s]+@)?([^:\/\s]+):(?!\/\/)(.+)/), !isDriveLetter(scp.1) {
            return clean("\(scp.1)/\(scp.2)")
        }

        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(),
              scheme != "file", var host = components.host, !host.isEmpty
        else { return nil }
        // WHATWG URL parsing, which upstream relies on, lowercases the host
        // only for these schemes.
        if ["http", "https", "ws", "wss", "ftp"].contains(scheme) { host = host.lowercased() }
        return clean(host + components.percentEncodedPath)
    }

    private static func clean(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") { result.removeLast() }
        if result.hasSuffix(".git") { result.removeLast(4) }
        return result.replacing(/\/{2,}/, with: "/")
    }

    private static func isDriveLetter(_ host: Substring) -> Bool {
        host.count == 1 && host.allSatisfy { $0.isASCII && $0.isLetter }
    }

    // .git is a directory, or a file pointing to one for worktrees and
    // submodules.
    private static func findGitDirectory(from root: String) -> String? {
        var directory = root
        while true {
            let candidate = directory == "/" ? "/.git" : directory + "/.git"
            switch FileStatus.follow(candidate)?.type {
            case .directory:
                return candidate
            case .regular:
                if let pointer = readSmallFile(candidate),
                   let match = pointer.firstMatch(of: /^gitdir:\s*(.+?)\s*$/.anchorsMatchLineEndings()) {
                    return resolvePath(String(match.1), relativeTo: directory)
                }
            default:
                break
            }
            let parent = (directory as NSString).deletingLastPathComponent
            if parent == directory || parent.isEmpty { return nil }
            directory = parent
        }
    }

    private static func resolvePath(_ path: String, relativeTo base: String) -> String {
        let joined = path.hasPrefix("/") ? path : base + "/" + path
        return (joined as NSString).standardizingPath
    }

    private static func readSmallFile(_ path: String) -> String? {
        guard let status = FileStatus.follow(path), status.type == .regular, status.size <= 256 * 1024,
              let data = FileManager.default.contents(atPath: path)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
