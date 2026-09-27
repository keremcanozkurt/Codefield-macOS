import Foundation
import Testing
@testable import Codefield

struct GitRemoteTests {
    @Test func acceptsRemotesOnAnyHost() {
        for remote in [
            "git@github.com:user/project.git",
            "git@gitlab.com:user/project.git",
            "git@bitbucket.org:user/project.git",
            "git@git.company.com:team/project.git",
            "ssh://git@codeberg.org/user/project.git",
            "https://gitea.example.com/user/project.git",
            "https://forgejo.example.org/team/project",
            "git://example.com/project.git",
            "file:///srv/git/project.git",
            "/srv/git/project.git",
            "/Users/me/My Repos/project",
            "../project",
        ] {
            #expect(GitRemote.problem(with: remote) == nil, "\(remote)")
        }
    }

    @Test func refusesRemotesGitCouldReadAsOptionsOrCommands() {
        for remote in [
            "--upload-pack=touch /tmp/x",
            "-u touch",
            "ext::sh -c touch% /tmp/x",
            "fd::17",
            "EXT::sh",
            "evil://host/repo",
            "git@host:repo\n--upload-pack=x",
            "git@host:repo\u{7F}",
            " git@host:repo",
            "git@host:repo ",
            "",
        ] {
            #expect(GitRemote.problem(with: remote) != nil, "\(remote.debugDescription)")
        }
    }

    @Test func picksTheFolderNameGitWould() {
        #expect(GitRemote.defaultDirectoryName("git@github.com:user/project.git") == "project")
        #expect(GitRemote.defaultDirectoryName("https://example.com/team/app/") == "app")
        #expect(GitRemote.defaultDirectoryName("git@host:app") == "app")
        #expect(GitRemote.defaultDirectoryName("C:\\repos\\tool.git") == "tool")
        #expect(GitRemote.defaultDirectoryName("git@host:") == nil)
        #expect(GitRemote.defaultDirectoryName("https://example.com/..") == nil)
    }

    @Test func passesRemoteAndDestinationAsPlainArgumentsAfterDoubleDash() {
        #expect(GitCloneCommand.arguments(remote: "$(touch x); rm -rf ~", destination: "/tmp/dest") == [
            "-c", "protocol.ext.allow=never", "clone", "--", "$(touch x); rm -rf ~", "/tmp/dest",
        ])
    }

    @Test func recognizesCommonGitAndSSHFailures() {
        #expect(GitCloneFailure.classify("Host key verification failed.\nfatal: Could not read from remote repository.") == .hostVerification)
        #expect(GitCloneFailure.classify("git@github.com: Permission denied (publickey).") == .sshPermission)
        #expect(GitCloneFailure.classify("ssh: Could not resolve hostname git.nowhere: nodename nor servname provided") == .network)
        #expect(GitCloneFailure.classify("fatal: unable to access 'https://x/': Failed to connect to x port 443") == .network)
        #expect(GitCloneFailure.classify("remote: Invalid username or password.\nfatal: Authentication failed for 'https://x/'") == .authentication)
        #expect(GitCloneFailure.classify("fatal: could not read Username for 'https://x': terminal prompts disabled") == .authentication)
        #expect(GitCloneFailure.classify("ERROR: Repository not found.\nfatal: Could not read from remote repository.") == .notFound)
        #expect(GitCloneFailure.classify("fatal: destination path 'x' already exists and is not an empty directory.") == .destinationExists)
        #expect(GitCloneFailure.classify("fatal: something unexpected") == .failed)
    }
}

struct CloneDestinationTests {
    @Test func placesTheCloneInsideTheRealParent() throws {
        let folder = try TemporaryFolder()
        try folder.write(["parent/keep.txt": ""])
        try folder.link("alias", to: folder.path + "/parent")

        #expect(CloneDestination.resolve(parentPath: folder.path + "/alias", name: "project") == .success(folder.path + "/parent/project"))
    }

    @Test func refusesToOverwriteAnything() throws {
        let folder = try TemporaryFolder()
        try folder.write(["taken/keep.txt": "mine", "file": ""])
        try FileManager.default.createDirectory(atPath: folder.path + "/empty", withIntermediateDirectories: false)

        #expect(CloneDestination.resolve(parentPath: folder.path, name: "taken") == .failure(.destinationExists))
        #expect(CloneDestination.resolve(parentPath: folder.path, name: "file") == .failure(.destinationExists))
        #expect(CloneDestination.resolve(parentPath: folder.path, name: "empty") == .success(folder.path + "/empty"))
        #expect(try String(contentsOfFile: folder.path + "/taken/keep.txt", encoding: .utf8) == "mine")
    }

    @Test func refusesNamesAndParentsThatLeaveTheChosenFolder() throws {
        let folder = try TemporaryFolder()
        try folder.write(["file": ""])
        for name in ["", ".", "..", "a/b", "../escape", "tab\there"] {
            #expect(CloneDestination.resolve(parentPath: folder.path, name: name) == .failure(.invalidDestination), "\(name)")
        }
        #expect(CloneDestination.resolve(parentPath: "relative/path", name: "x") == .failure(.invalidDestination))
        #expect(CloneDestination.resolve(parentPath: folder.path + "/file", name: "x") == .failure(.invalidDestination))
        #expect(CloneDestination.resolve(parentPath: folder.path + "/missing", name: "x") == .failure(.invalidDestination))
    }
}

struct GitProcessTests {
    @Test func prefersHomebrewGitAndNeedsDeveloperToolsForUsrBinGit() {
        let homebrew: Set = ["/opt/homebrew/bin/git", "/usr/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git"]
        #expect(GitExecutable.find(isExecutable: homebrew.contains, developerDirectory: { nil })?.path == "/opt/homebrew/bin/git")

        let tools: Set = ["/usr/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git"]
        #expect(GitExecutable.find(isExecutable: tools.contains, developerDirectory: { "/Library/Developer/CommandLineTools" })?.path == "/usr/bin/git")

        // /usr/bin/git without developer tools only offers to install them.
        #expect(GitExecutable.find(isExecutable: { $0 == "/usr/bin/git" }, developerDirectory: { nil }) == nil)
    }

    @Test func keepsTheUsersEnvironmentAndTurnsOffPrompts() {
        let environment = GitEnvironment.make(from: [
            "PATH": "/usr/bin:/bin",
            "SSH_AUTH_SOCK": "/private/tmp/agent",
            "HOME": "/Users/me",
            "GIT_SSH_COMMAND": "ssh -i ~/.ssh/work",
        ])
        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(environment["SSH_AUTH_SOCK"] == "/private/tmp/agent")
        #expect(environment["GIT_SSH_COMMAND"] == "ssh -i ~/.ssh/work")
        #expect(environment["PATH"] == "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin")
    }

    // /bin/ls stands in for git: it names every operand it cannot find on
    // standard error, which shows each argument arrived whole and unexpanded.
    @Test func runsWithoutAShell() async throws {
        let folder = try TemporaryFolder()
        let marker = folder.path + "/pwned"
        let remote = "$(touch \(marker));`touch \(marker)`|x"
        let (failure, output) = await run(executable: "/bin/ls", remote: remote, destination: folder.path + "/dest")

        #expect(failure == .failed)
        #expect(output.contains(remote))
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test func reportsSuccessAndMissingExecutables() async throws {
        let folder = try TemporaryFolder()
        #expect(await run(executable: "/usr/bin/true", remote: "r", destination: folder.path + "/d").0 == nil)
        #expect(await run(executable: folder.path + "/no-git", remote: "r", destination: folder.path + "/d").0 == .gitMissing)
    }

    @Test func stopsWhenCancelled() async throws {
        let folder = try TemporaryFolder()
        let runner = GitCloneRunner()
        // /usr/bin/yes runs until it is stopped.
        let failure: GitCloneFailure? = await withCheckedContinuation { continuation in
            runner.run(executable: URL(filePath: "/usr/bin/yes"), remote: "r", destination: folder.path + "/d", environment: [:]) { result, _ in
                continuation.resume(returning: Self.failure(of: result))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { runner.cancel() }
        }
        #expect(failure == .cancelled)
    }

    private func run(executable: String, remote: String, destination: String) async -> (GitCloneFailure?, String) {
        await withCheckedContinuation { continuation in
            GitCloneRunner().run(executable: URL(filePath: executable), remote: remote, destination: destination, environment: [:]) { result, output in
                continuation.resume(returning: (Self.failure(of: result), output))
            }
        }
    }

    private static func failure(of result: Result<Void, GitCloneFailure>) -> GitCloneFailure? {
        if case .failure(let failure) = result { failure } else { nil }
    }
}
