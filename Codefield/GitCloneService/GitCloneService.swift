import Foundation

final class GitCloneService: NSObject, GitCloneServiceProtocol, @unchecked Sendable {
    private let runner = GitCloneRunner()

    // Everything the app sent is checked again here: this is the process that
    // runs git and can write outside the sandbox.
    func clone(remote: String, parentPath: String, directoryName: String, reply: @escaping @Sendable (String?, String?) -> Void) {
        if let problem = GitRemote.problem(with: remote) {
            reply(GitCloneFailure.invalidRemote.rawValue, problem)
            return
        }
        let destination: String
        switch CloneDestination.resolve(parentPath: parentPath, name: directoryName) {
        case .success(let path):
            destination = path
        case .failure(let failure):
            reply(failure.rawValue, nil)
            return
        }
        guard let git = GitExecutable.find() else {
            reply(GitCloneFailure.gitMissing.rawValue, nil)
            return
        }
        runner.run(
            executable: git,
            remote: remote,
            destination: destination,
            environment: GitEnvironment.make(from: ProcessInfo.processInfo.environment)
        ) { result, output in
            switch result {
            case .success: reply(nil, nil)
            case .failure(let failure): reply(failure.rawValue, output)
            }
        }
    }

    func cancel() {
        runner.cancel()
    }
}
