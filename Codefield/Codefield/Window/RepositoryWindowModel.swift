import AppKit
import Observation
import OSLog

private let log = Logger(subsystem: "com.keremcanozkurt.Codefield", category: "analysis")

enum AnalysisProgress: Equatable {
    case readingRepository(files: Int)
    case readingSources(read: Int, total: Int)
    case analyzing(files: Int)
    case buildingGraph(files: Int)
    case rendering

    var label: String {
        switch self {
        case .readingRepository: "Reading repository…"
        case .readingSources: "Reading source files…"
        case .analyzing: "Analyzing dependencies…"
        case .buildingGraph: "Building graph…"
        case .rendering: "Rendering…"
        }
    }

    var detail: String? {
        switch self {
        case .readingRepository(let files):
            files > 0 ? "\(formatCount(files, "file", "files")) found" : nil
        case .readingSources(let read, let total):
            "\(read.formatted()) of \(formatCount(total, "source file", "source files")) read"
        case .analyzing(let files), .buildingGraph(let files):
            formatCount(files, "source file", "source files")
        case .rendering:
            nil
        }
    }
}

func formatCount(_ value: Int, _ singular: String, _ plural: String) -> String {
    "\(value.formatted()) \(value == 1 ? singular : plural)"
}

// One window: the repository it shows, the analysis in progress, and the
// workspace page. The page owns everything inside the workspace (view,
// selection, search, filters); the window owns which folder is read and when.
@Observable
final class RepositoryWindowModel {
    private(set) var repository: OpenedRepository?
    private(set) var git: GitMetadata?
    private(set) var progress: AnalysisProgress?
    private(set) var outcome: AnalysisOutcome?
    // False from opening a repository until its first analysis is on screen;
    // until then the native progress view covers the page.
    private(set) var isRevealed = false
    private(set) var failure: String?
    var alert: String?

    let recents: RecentRepositoryStore

    @ObservationIgnored private let makePage: () -> any WorkspacePage
    @ObservationIgnored private var webController: (any WorkspacePage)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var filesRead = 0

    init(recents: RecentRepositoryStore = .shared, makePage: @escaping () -> any WorkspacePage = { WorkspaceWebController() }) {
        self.recents = recents
        self.makePage = makePage
    }

    var web: any WorkspacePage {
        if let webController { return webController }
        let controller = makePage()
        controller.onMessage = { [weak self] in self?.receive($0) }
        controller.onPageReset = { [weak self] in self?.pageReset() }
        webController = controller
        return controller
    }

    var isAnalyzing: Bool { progress != nil }

    var subtitle: String {
        if isRevealed, let progress { return progress.label }
        guard repository != nil else { return "" }
        return [git?.branch, git?.remote].compactMap(\.self).joined(separator: " · ")
    }

    // MARK: Opening

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        panel.message = "Choose a repository folder to analyze."
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let url = panel.url { self?.open(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func open(_ url: URL) {
        let access = RepositoryAccess(url: url)
        switch RepositoryRoot.resolve(url) {
        case .failure(let error):
            alert = error.message
        case .success(let path):
            let isSameFolder = repository?.path == path
            repository = OpenedRepository(path: path, access: access)
            recents.noteOpened(url)
            analyze(fresh: !isSameFolder)
        }
    }

    func openRecent(_ item: RecentRepository) {
        guard let url = recents.resolve(item) else {
            alert = "“\(item.name)” could not be found. It may have been moved or deleted."
            return
        }
        open(url)
    }

    // Folders only; the drop goes through the same checks as the open panel.
    func openDropped(_ urls: [URL]) -> Bool {
        guard urls.count == 1, let url = urls.first else { return false }
        guard case .success = RepositoryRoot.resolve(url) else { return false }
        open(url)
        return true
    }

    func close() {
        cancel()
        webController?.tearDown()
        webController = nil
        repository = nil
    }

    // MARK: Analysis

    func analyzeAgain() {
        guard repository != nil else { return }
        analyze(fresh: false)
    }

    func showFAQ() {
        guard webController?.isReady == true else { return }
        Task { _ = try? await web.send(.showFAQ) }
    }

    func focusSearch() {
        guard isRevealed, webController?.isReady == true else { return }
        web.focus()
        Task { _ = try? await web.send(.focusSearch) }
    }

    private func analyze(fresh: Bool) {
        guard let repository else { return }
        cancel()
        run += 1
        let run = run
        if fresh {
            isRevealed = false
            outcome = nil
            git = nil
        }
        failure = nil
        progress = .readingRepository(files: 0)
        let web = web
        task = Task { await perform(run: run, fresh: fresh, repository: repository, web: web) }
    }

    private func cancel() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        let cancelled = run
        if let webController, webController.isReady {
            Task { _ = try? await webController.send(.cancel(run: cancelled)) }
        }
    }

    private func perform(run: Int, fresh: Bool, repository: OpenedRepository, web: any WorkspacePage) async {
        await web.waitUntilReady()
        do {
            try Task.checkCancellation()
            let root = repository.path
            async let metadata = Self.readGit(root: root)
            let listing = try await RepositoryWalker.list(root: root) { [weak self] files in
                self?.report(run, .readingRepository(files: files))
            }
            let git = await metadata
            try Task.checkCancellation()
            self.git = git

            let identity = RepositoryIdentity(name: repository.name, branch: git?.branch, remote: git?.remote)
            let begin = try await web.send(.begin(run: run, fresh: fresh, repository: identity, listing: listing))
            try Task.checkCancellation()

            switch BeginReply(reply: begin) {
            case .outcome(let outcome):
                finish(run, outcome)
            case .read(let sources, let configs):
                // The page asks only for files the walk found; anything else
                // is refused rather than read.
                let known = Set(listing.files.map(\.path))
                guard sources.allSatisfy(known.contains), configs.allSatisfy(known.contains) else {
                    log.error("The workspace page asked for a file outside the listing.")
                    try await web.send(.fail(run: run, error: .failed))
                    return finish(run, .error)
                }
                try await readAndAnalyze(run: run, repository: repository, sources: sources, configs: configs, web: web)
            case nil:
                throw WorkspaceBridgeError.pageUnavailable
            }
        } catch is CancellationError {
            return
        } catch {
            guard run == self.run, !Task.isCancelled else { return }
            log.error("Analysis failed: \(String(describing: error), privacy: .public)")
            _ = try? await web.send(.fail(run: run, error: .failed))
            finish(run, .error, failure: "The workspace stopped responding. Try Analyze Again.")
        }
    }

    private func readAndAnalyze(
        run: Int,
        repository: OpenedRepository,
        sources: [String],
        configs: [String],
        web: any WorkspacePage
    ) async throws {
        let reader = SourceReader(root: repository.path)
        let configFiles = await SourceLoader.readConfigs(reader, paths: configs)
        try Task.checkCancellation()
        try await web.send(.configs(run: run, files: configFiles))

        var next = 0
        var textUnits = 0
        var read = 0
        report(run, .readingSources(read: 0, total: sources.count))
        while next < sources.count {
            let batch = try await SourceLoader.readBatch(reader, paths: sources, from: next, textUnits: textUnits)
            try Task.checkCancellation()
            if batch.exceeded {
                try await web.send(.fail(run: run, error: .resourcesExceeded))
                return finish(run, .error)
            }
            try await web.send(.sources(run: run, files: batch.files, skipped: batch.skipped))
            next = batch.next
            textUnits = batch.textUnits
            read += batch.files.count
            report(run, .readingSources(read: next, total: sources.count))
        }

        try Task.checkCancellation()
        report(run, .analyzing(files: read))
        filesRead = read
        let reply = try await web.send(.finish(run: run))
        try Task.checkCancellation()
        finish(run, AnalysisOutcome(reply: reply) ?? .error)
    }

    @concurrent
    private nonisolated static func readGit(root: String) async -> GitMetadata? {
        GitMetadata.read(root: root)
    }

    private func report(_ run: Int, _ progress: AnalysisProgress) {
        guard run == self.run, self.progress != nil else { return }
        self.progress = progress
    }

    private func finish(_ run: Int, _ outcome: AnalysisOutcome, failure: String? = nil) {
        guard run == self.run else { return }
        task = nil
        progress = nil
        if outcome != .cancelled { self.outcome = outcome }
        self.failure = failure
        isRevealed = failure == nil
        if isRevealed { webController?.focus() }
    }

    private func receive(_ message: PageMessage) {
        switch message {
        case .ready:
            break
        case .progress(let run, let stage):
            switch stage {
            case .analysis: report(run, .analyzing(files: filesRead))
            case .graph: report(run, .buildingGraph(files: filesRead))
            case .render: report(run, .rendering)
            }
        case .analyzeAgain:
            analyzeAgain()
        }
    }

    private func pageReset() {
        task?.cancel()
        task = nil
        guard repository != nil else { return }
        progress = nil
        isRevealed = false
        analyze(fresh: true)
    }
}
