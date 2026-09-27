import Foundation

nonisolated enum GitExecutable {
    // Homebrew's git first, as a Terminal with Homebrew on its PATH would
    // pick it. /usr/bin/git is only a launcher for the developer tools; with
    // none installed it opens the install dialog instead of running, so it is
    // used only when xcode-select reports a developer directory with git in it.
    static func find(
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        developerDirectory: () -> String? = currentDeveloperDirectory
    ) -> URL? {
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where isExecutable(path) {
            return URL(filePath: path)
        }
        if let developer = developerDirectory(), isExecutable(developer + "/usr/bin/git"), isExecutable("/usr/bin/git") {
            return URL(filePath: "/usr/bin/git")
        }
        return nil
    }

    static func currentDeveloperDirectory() -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcode-select")
        process.arguments = ["--print-path"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

nonisolated enum GitEnvironment {
    // The user's own environment, so SSH_AUTH_SOCK, HOME, GIT_SSH_COMMAND and
    // credential helpers work as in Terminal. Git must never wait for input
    // nobody can type, so its own prompts are turned off; SSH has no terminal
    // either, which makes an unknown host key fail instead of being accepted.
    static func make(from environment: [String: String]) -> [String: String] {
        var result = environment
        result["GIT_TERMINAL_PROMPT"] = "0"
        // Processes started by launchd get a minimal PATH, without the
        // Homebrew locations where helpers such as git-lfs usually live.
        var path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !path.contains(directory) {
            path.append(directory)
        }
        result["PATH"] = path.joined(separator: ":")
        return result
    }
}

// Runs one git clone and reports how it ended. Standard input is closed and
// git's error output is kept only as a short tail for the failure details.
nonisolated final class GitCloneRunner: @unchecked Sendable {
    static let stderrTailBytes = 16 * 1024

    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func run(
        executable: URL,
        remote: String,
        destination: String,
        environment: [String: String],
        completion: @escaping @Sendable (Result<Void, GitCloneFailure>, String) -> Void
    ) {
        let process = Process()
        process.executableURL = executable
        process.arguments = GitCloneCommand.arguments(remote: remote, destination: destination)
        process.environment = environment
        process.currentDirectoryURL = URL(filePath: (destination as NSString).deletingLastPathComponent)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        let errorPipe = Pipe()
        process.standardError = errorPipe
        let tail = StderrTail(limit: Self.stderrTailBytes)
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            tail.append(handle.availableData)
        }

        process.terminationHandler = { [weak self] finished in
            errorPipe.fileHandleForReading.readabilityHandler = nil
            tail.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            let output = tail.text
            let wasCancelled = self?.finish() ?? false
            if wasCancelled {
                completion(.failure(.cancelled), output)
            } else if finished.terminationReason == .exit, finished.terminationStatus == 0 {
                completion(.success(()), output)
            } else {
                completion(.failure(GitCloneFailure.classify(output)), output)
            }
        }

        lock.lock()
        if cancelled {
            lock.unlock()
            completion(.failure(.cancelled), "")
            return
        }
        do {
            try process.run()
            self.process = process
            lock.unlock()
        } catch {
            lock.unlock()
            completion(.failure(.gitMissing), "")
        }
    }

    // git removes a partial clone itself when it is stopped.
    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if let running, running.isRunning { running.terminate() }
    }

    private func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        process = nil
        return cancelled
    }
}

private nonisolated final class StderrTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        if data.count > limit { data.removeFirst(data.count - limit) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
