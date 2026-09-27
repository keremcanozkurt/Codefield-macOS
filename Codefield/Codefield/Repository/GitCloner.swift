import Foundation

struct CloneOutcome: Equatable, Sendable {
    var failure: GitCloneFailure?
    // The end of git's error output, for the failure details.
    var detail: String?

    static let success = CloneOutcome(failure: nil, detail: nil)
}

protocol RepositoryCloner: AnyObject {
    func clone(remote: String, parentPath: String, directoryName: String) async -> CloneOutcome
    func cancel()
}

// Talks to GitCloneService, the helper bundled in the app that runs git
// outside the sandbox. git started by the sandboxed app would inherit its
// sandbox: ssh could not read ~/.ssh or reach the SSH agent, and git could
// not write the clone.
final class ServiceCloner: RepositoryCloner {
    private var connection: NSXPCConnection?

    func clone(remote: String, parentPath: String, directoryName: String) async -> CloneOutcome {
        let connection = NSXPCConnection(serviceName: GitCloneServiceName.value)
        connection.remoteObjectInterface = NSXPCInterface(with: GitCloneServiceProtocol.self)
        connection.resume()
        self.connection = connection
        defer {
            connection.invalidate()
            if self.connection === connection { self.connection = nil }
        }

        return await withCheckedContinuation { continuation in
            let reply = ReplyOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                reply.resume(CloneOutcome(failure: .failed, detail: "The clone helper stopped unexpectedly."))
            }
            guard let service = proxy as? GitCloneServiceProtocol else {
                reply.resume(CloneOutcome(failure: .failed, detail: nil))
                return
            }
            service.clone(remote: remote, parentPath: parentPath, directoryName: directoryName) { failure, detail in
                let outcome = failure.map { CloneOutcome(failure: GitCloneFailure(rawValue: $0) ?? .failed, detail: detail) } ?? .success
                reply.resume(outcome)
            }
        }
    }

    func cancel() {
        (connection?.remoteObjectProxy as? GitCloneServiceProtocol)?.cancel()
    }
}

// The reply and the connection's error handler can both fire; the first wins.
private nonisolated final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CloneOutcome, Never>?

    init(_ continuation: CheckedContinuation<CloneOutcome, Never>) {
        self.continuation = continuation
    }

    func resume(_ outcome: CloneOutcome) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: outcome)
    }
}

// The folder the last clone went into, offered again next time. Stored as a
// read-only security-scoped bookmark, like the recent repositories.
final class CloneParentFolder {
    private let defaults: UserDefaults
    private let key: String
    private let bookmarks: Bookmarks

    init(defaults: UserDefaults = .standard, key: String = "CloneParentFolder", bookmarks: Bookmarks = .securityScoped) {
        self.defaults = defaults
        self.key = key
        self.bookmarks = bookmarks
    }

    var url: URL? {
        guard let data = defaults.data(forKey: key), let resolved = try? bookmarks.resolve(data) else { return nil }
        if resolved.isStale, let renewed = try? bookmarks.make(resolved.url) { defaults.set(renewed, forKey: key) }
        return resolved.url
    }

    func remember(_ url: URL) {
        if let data = try? bookmarks.make(url) { defaults.set(data, forKey: key) }
    }
}
