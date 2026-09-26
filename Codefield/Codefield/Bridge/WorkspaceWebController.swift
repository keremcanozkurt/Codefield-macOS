import AppKit
import OSLog
import WebKit

private let log = Logger(subsystem: "com.keremcanozkurt.Codefield", category: "workspace")

enum WorkspaceBridgeError: Error {
    case pageUnavailable
}

// What a window needs from its workspace page; tests substitute a page that
// answers without WebKit.
protocol WorkspacePage: AnyObject {
    var view: NSView { get }
    var isReady: Bool { get }
    var onMessage: (PageMessage) -> Void { get set }
    var onPageReset: () -> Void { get set }
    func waitUntilReady() async
    @discardableResult func send(_ message: NativeMessage) async throws -> Any?
    func focus()
    func tearDown()
}

// Owns one window's WKWebView. The page it shows is bundled and served by
// WorkspaceSchemeHandler; any other navigation is refused, links to the
// Codefield site open in the default browser, and a PNG export is saved to
// Downloads.
final class WorkspaceWebController: NSObject, WorkspacePage {
    let webView: WKWebView
    var onMessage: (PageMessage) -> Void = { _ in }
    var onPageReset: () -> Void = {}

    private(set) var isReady = false
    private var exports: [ObjectIdentifier: URL] = [:]
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(WorkspaceSchemeHandler(), forURLScheme: WorkspaceSchemeHandler.scheme)
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        configuration.userContentController.add(MessageProxy(self), name: "codefield")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = Theme.backgroundColor
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.load(URLRequest(url: WorkspaceSchemeHandler.pageURL))

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !self.isReady else { return }
            log.error("The workspace page did not report ready.")
            self.resumeWaiters()
        }
    }

    var view: NSView { webView }

    func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    @discardableResult
    func send(_ message: NativeMessage) async throws -> Any? {
        guard isReady else { throw WorkspaceBridgeError.pageUnavailable }
        return try await webView.callAsyncJavaScript(
            "return await window.codefield.receive(message)",
            arguments: ["message": message.payload],
            contentWorld: .page
        )
    }

    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    func tearDown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "codefield")
        webView.stopLoading()
        resumeWaiters()
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == WorkspaceSchemeHandler.scheme,
              message.frameInfo.securityOrigin.host == WorkspaceSchemeHandler.host,
              let parsed = PageMessage(body: message.body)
        else {
            log.error("Dropped a malformed message from the workspace page.")
            return
        }
        if parsed == .ready {
            isReady = true
            resumeWaiters()
        }
        onMessage(parsed)
    }

    private func resumeWaiters() {
        let waiters = readyWaiters
        readyWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}

extension WorkspaceWebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }

        if action.shouldPerformDownload {
            // Export PNG clicks a blob: link with a download attribute.
            return url.scheme == "blob" ? .download : .cancel
        }
        if WorkspaceSchemeHandler.resource(for: url) != nil, action.targetFrame?.isMainFrame == true {
            return .allow
        }
        if action.navigationType == .linkActivated { ExternalLinks.open(url) }
        return .cancel
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // A page that cannot load leaves anyone waiting for it to fail on their
    // first message instead of waiting forever.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        log.error("The workspace page did not load: \(error.localizedDescription, privacy: .public)")
        resumeWaiters()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        log.error("The workspace page did not load: \(error.localizedDescription, privacy: .public)")
        resumeWaiters()
    }

    // The page's state is gone with its process; the window analyzes again
    // once the reloaded page reports ready.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("The workspace page's process ended; reloading.")
        isReady = false
        onPageReset()
        webView.load(URLRequest(url: WorkspaceSchemeHandler.pageURL))
    }
}

extension WorkspaceWebController: WKUIDelegate {
    // target="_blank" links, such as Support.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url { ExternalLinks.open(url) }
        return nil
    }
}

extension WorkspaceWebController: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard let name = ExportFile.acceptedName(suggestedFilename),
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        else {
            log.error("Refused a download that is not a PNG export.")
            return nil
        }
        let destination = ExportFile.availableURL(for: name, in: downloads)
        exports[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        // The notification Safari posts, which bounces the Downloads stack in
        // the Dock.
        if let destination = exports.removeValue(forKey: ObjectIdentifier(download)) {
            DistributedNotificationCenter.default().post(
                name: .init("com.apple.DownloadFileFinished"),
                object: destination.resolvingSymlinksInPath().path(percentEncoded: false)
            )
        }
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        exports.removeValue(forKey: ObjectIdentifier(download))
        log.error("PNG export could not be saved: \(error.localizedDescription, privacy: .public)")
    }
}

// WKUserContentController keeps its handlers strongly; the proxy keeps the
// controller from owning itself through its own web view.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var controller: WorkspaceWebController?

    init(_ controller: WorkspaceWebController) {
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        controller?.receive(message)
    }
}

enum ExternalLinks {
    static let support = URL(string: "https://codefield.keremcanozkurt.com/support")!

    // The page only links to the Codefield site. Anything else a page could
    // produce is not opened.
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host()?.lowercased() == "codefield.keremcanozkurt.com"
    }

    static func open(_ url: URL) {
        guard isAllowed(url) else {
            log.error("Refused to open a link outside the Codefield site.")
            return
        }
        NSWorkspace.shared.open(url)
    }
}

nonisolated enum ExportFile {
    // Upstream's exportFileName: codefield-<repository>.png, already limited
    // to letters, digits, ".", "_" and "-".
    static func acceptedName(_ suggested: String) -> String? {
        suggested.wholeMatch(of: /codefield-[A-Za-z0-9._-]+\.png/) == nil ? nil : suggested
    }

    // "codefield-x.png", then "codefield-x 2.png" and so on, as Finder names
    // copies.
    static func availableURL(for name: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        let base = (name as NSString).deletingPathExtension
        var candidate = directory.appending(path: name)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appending(path: "\(base) \(number).png")
            number += 1
        }
        return candidate
    }
}
