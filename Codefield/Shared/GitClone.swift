import Foundation

// Compiled into both the app and GitCloneService. The rules follow upstream
// cli/clone.mjs, so a remote the command line refuses is refused here too.

nonisolated enum GitRemote {
    // Transports git may be asked to use. "ext::" and other remote-helper forms
    // ("<helper>::<address>") are refused: ext:: runs an arbitrary command.
    static let allowedSchemes: Set<String> = ["ssh", "git", "http", "https", "file", "git+ssh", "ssh+git"]

    // Why the remote cannot be cloned, or nil when it can be passed to git.
    static func problem(with remote: String) -> String? {
        if remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a Git remote." }
        if remote != remote.trimmingCharacters(in: .whitespacesAndNewlines)
            || remote.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return "The remote starts or ends with a space, or contains control characters."
        }
        // Would otherwise be read by git as an option, such as --upload-pack=<command>.
        if remote.hasPrefix("-") { return "The remote cannot start with “-”." }
        if remote.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*::/) != nil {
            return "Git remote helpers such as ext:: are not supported."
        }
        if let scheme = remote.firstMatch(of: /^([A-Za-z][A-Za-z0-9+.\-]*):\/\//), !allowedSchemes.contains(scheme.1.lowercased()) {
            return "Unsupported transport: \(scheme.1)://"
        }
        return nil
    }

    // The folder name git itself would pick: the last path segment of the
    // remote, without a trailing ".git".
    static func defaultDirectoryName(_ remote: String) -> String? {
        var path = remote
        while path.hasSuffix("/") || path.hasSuffix("\\") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        while path.hasSuffix("/") || path.hasSuffix("\\") { path.removeLast() }
        let name = path.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "\\" || $0 == ":" })
            .last.map(String.init) ?? ""
        guard CloneDestination.isValidName(name) else { return nil }
        return name
    }
}

nonisolated enum CloneDestination {
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
            && !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    }

    // The folder the clone goes into: a new name inside an existing parent,
    // with the parent's symbolic links resolved so the clone cannot land
    // anywhere but where the user can see it.
    static func resolve(parentPath: String, name: String) -> Result<String, GitCloneFailure> {
        guard parentPath.hasPrefix("/"), isValidName(name), let real = realpath(parentPath, nil) else {
            return .failure(.invalidDestination)
        }
        let parent = String(cString: real)
        free(real)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.invalidDestination)
        }

        let destination = parent == "/" ? "/" + name : parent + "/" + name
        if FileManager.default.fileExists(atPath: destination, isDirectory: &isDirectory) {
            // git itself accepts an existing empty directory.
            let empty = isDirectory.boolValue && ((try? FileManager.default.contentsOfDirectory(atPath: destination))?.isEmpty ?? false)
            if !empty { return .failure(.destinationExists) }
        }
        return .success(destination)
    }
}

nonisolated enum GitCloneCommand {
    // The remote and destination are separate arguments after "--": never
    // parsed by a shell, never read as options.
    static func arguments(remote: String, destination: String) -> [String] {
        ["-c", "protocol.ext.allow=never", "clone", "--", remote, destination]
    }
}

nonisolated enum GitCloneFailure: String, Error, Equatable, Sendable {
    case gitMissing = "git_missing"
    case destinationExists = "destination_exists"
    case invalidDestination = "invalid_destination"
    case invalidRemote = "invalid_remote"
    case hostVerification = "host_verification"
    case sshPermission = "ssh_permission"
    case authentication
    case notFound = "not_found"
    case network
    case cancelled
    case failed

    static func classify(_ stderr: String) -> GitCloneFailure {
        func matches(_ pattern: String) -> Bool {
            stderr.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if matches("already exists and is not an empty directory") { return .destinationExists }
        if matches("Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED") { return .hostVerification }
        if matches("Permission denied \\((publickey|keyboard-interactive|password)") { return .sshPermission }
        if matches("Authentication failed|could not read (Username|Password)|terminal prompts disabled|Invalid username or password") {
            return .authentication
        }
        if matches("Could not resolve host|Could not resolve hostname|Connection timed out|Connection refused|Network is unreachable|Operation timed out|Failed to connect") {
            return .network
        }
        if matches("Repository not found|does not appear to be a git repository|not found|does not exist") { return .notFound }
        return .failed
    }

    var title: String {
        switch self {
        case .gitMissing: "Git is not installed"
        case .destinationExists: "Destination already exists"
        case .invalidDestination: "Destination unavailable"
        case .invalidRemote: "Remote not supported"
        case .hostVerification: "Host verification failed"
        case .sshPermission: "SSH key refused"
        case .authentication: "Authentication failed"
        case .notFound: "Repository not found or unavailable"
        case .network: "Network unavailable"
        case .cancelled: "Clone cancelled"
        case .failed: "Clone failed"
        }
    }

    var message: String {
        switch self {
        case .gitMissing:
            "Codefield clones with the Git installed on your Mac. Install the Xcode Command Line Tools (xcode-select --install) or Git from Homebrew."
        case .destinationExists:
            "A file or a non-empty folder with that name is already there. Choose another name or folder."
        case .invalidDestination:
            "The destination folder could not be found."
        case .invalidRemote:
            "Git cannot clone this remote."
        case .hostVerification:
            "SSH could not verify the server's host key. Connect once with ssh in Terminal to check and accept it, or fix ~/.ssh/known_hosts. Codefield never accepts host keys for you."
        case .sshPermission:
            "The SSH server refused your key. Check that it is loaded (ssh-add -l) and has access to this repository."
        case .authentication:
            "Git could not authenticate with your existing credentials. Some hosts also answer this way when the repository does not exist."
        case .notFound:
            "Git could not access the repository. It may not exist, or your account may not have access to it."
        case .network:
            "Git could not reach the server. Check the host name and your network connection."
        case .cancelled:
            "Nothing was kept."
        case .failed:
            "Git could not clone the repository. Its output below has the details."
        }
    }
}

@objc(CodefieldGitCloneService)
protocol GitCloneServiceProtocol {
    // Replies with nil on success, or a GitCloneFailure raw value and the end
    // of git's error output.
    func clone(remote: String, parentPath: String, directoryName: String, reply: @escaping @Sendable (String?, String?) -> Void)
    func cancel()
}

nonisolated enum GitCloneServiceName {
    static let value = "com.keremcanozkurt.Codefield.GitCloneService"
}
