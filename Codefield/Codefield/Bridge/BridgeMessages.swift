import Foundation

// The message protocol between the app and the workspace page. The page's
// side, with the same message names, is Web/src/bridge.ts.
//
// App to page: WKWebView.callAsyncJavaScript calls window.codefield.receive
// with the message as an argument (never spliced into source text) and
// returns what the page's promise resolves to.
//
// Page to app: window.webkit.messageHandlers.codefield.postMessage.

nonisolated struct RepositoryIdentity: Equatable, Sendable {
    var name: String
    var branch: String?
    var remote: String?
}

nonisolated enum AnalysisFailure: String, Equatable, Sendable {
    case rootUnavailable = "root_unavailable"
    case resourcesExceeded = "resources_exceeded"
    case failed
}

nonisolated enum NativeMessage: Sendable {
    // `fresh` starts a new workspace session: a different repository, so no
    // selection or view carries over.
    case begin(run: Int, fresh: Bool, repository: RepositoryIdentity, listing: RepositoryListing)
    case configs(run: Int, files: [SourceText])
    case sources(run: Int, files: [SourceText], skipped: [SkippedFile])
    case finish(run: Int)
    case fail(run: Int, error: AnalysisFailure)
    case cancel(run: Int)
    case focusSearch

    // Property-list values only: callAsyncJavaScript converts them to
    // JavaScript objects, arrays, strings and numbers.
    var payload: [String: Any] {
        switch self {
        case let .begin(run, fresh, repository, listing):
            return [
                "type": "analysis.begin",
                "run": run,
                "fresh": fresh,
                "repository": [
                    "name": repository.name,
                    "branch": repository.branch.map { $0 as Any } ?? NSNull(),
                    "remote": repository.remote.map { $0 as Any } ?? NSNull(),
                ] as [String: Any],
                "listing": [
                    "files": listing.files.map { [$0.path, $0.size] as [Any] },
                    "symlinks": listing.symlinks,
                    "unreadableDirectories": listing.unreadableDirectories,
                ] as [String: Any],
            ]
        case let .configs(run, files):
            return ["type": "analysis.configs", "run": run, "files": files.map { [$0.path, $0.text] }]
        case let .sources(run, files, skipped):
            return [
                "type": "analysis.sources",
                "run": run,
                "files": files.map { [$0.path, $0.text] },
                "skipped": skipped.map { [$0.path, $0.reason.rawValue] },
            ]
        case let .finish(run):
            return ["type": "analysis.finish", "run": run]
        case let .fail(run, error):
            return ["type": "analysis.fail", "run": run, "error": error.rawValue]
        case let .cancel(run):
            return ["type": "analysis.cancel", "run": run]
        case .focusSearch:
            return ["type": "workspace.focusSearch"]
        }
    }
}

nonisolated enum AnalysisOutcome: Equatable, Sendable {
    case success(files: Int, edges: Int)
    case empty
    case unsupported
    case error
    case cancelled

    init?(reply: Any?) {
        guard let object = reply as? [String: Any], let status = object["status"] as? String else { return nil }
        switch status {
        case "success":
            guard let files = BridgeValue.count(object["files"]), let edges = BridgeValue.count(object["edges"]) else { return nil }
            self = .success(files: files, edges: edges)
        case "empty": self = .empty
        case "unsupported": self = .unsupported
        case "error": self = .error
        case "cancelled": self = .cancelled
        default: return nil
        }
    }
}

// The page's reply to .begin: the files it needs, or the outcome when the
// listing alone decides it.
nonisolated enum BeginReply: Equatable, Sendable {
    case read(sources: [String], configs: [String])
    case outcome(AnalysisOutcome)

    init?(reply: Any?) {
        guard let object = reply as? [String: Any] else { return nil }
        if let read = object["read"] as? [String: Any] {
            guard let sources = read["sources"] as? [String], let configs = read["configs"] as? [String] else { return nil }
            self = .read(sources: sources, configs: configs)
        } else if let outcome = AnalysisOutcome(reply: object["outcome"]) {
            self = .outcome(outcome)
        } else {
            return nil
        }
    }
}

nonisolated enum PageMessage: Equatable, Sendable {
    enum Stage: String, Sendable {
        case analysis, graph, render
    }

    case ready
    case progress(run: Int, stage: Stage)
    case analyzeAgain

    // Anything that does not match exactly is dropped.
    init?(body: Any) {
        guard let object = body as? [String: Any], let type = object["type"] as? String else { return nil }
        switch type {
        case "ready" where object.count == 1:
            self = .ready
        case "analyzeAgain" where object.count == 1:
            self = .analyzeAgain
        case "progress" where object.count == 3:
            guard let run = BridgeValue.count(object["run"]), run > 0,
                  let stage = (object["stage"] as? String).flatMap(Stage.init(rawValue:))
            else { return nil }
            self = .progress(run: run, stage: stage)
        default:
            return nil
        }
    }
}

nonisolated enum BridgeValue {
    // A non-negative whole number. JavaScript numbers arrive as NSNumber,
    // and so do booleans, which are refused.
    static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double >= 0, double <= Double(Int.max), double.rounded() == double else { return nil }
        return Int(double)
    }
}
