import Foundation
import WebKit

// Serves the workspace page from the app bundle under codefield://workspace/.
// Only the four built files are served; the page has no other way to reach
// the file system, and nothing is loaded from the network.
final class WorkspaceSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "codefield"
    nonisolated static let host = "workspace"
    nonisolated static let pageURL = URL(string: "codefield://workspace/workspace.html")!

    nonisolated static let files: [String: String] = [
        "workspace.html": "text/html; charset=utf-8",
        "workspace.js": "text/javascript; charset=utf-8",
        "workspace.css": "text/css; charset=utf-8",
        "analysis-worker.js": "text/javascript; charset=utf-8",
    ]

    nonisolated static func resource(for url: URL) -> (name: String, mimeType: String)? {
        guard url.scheme == scheme, url.host() == host, url.query() == nil else { return nil }
        let path = url.path(percentEncoded: true)
        guard path.hasPrefix("/"), !path.dropFirst().contains("/") else { return nil }
        let name = String(path.dropFirst())
        guard let mimeType = files[name] else { return nil }
        return (name, mimeType)
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let resource = Self.resource(for: url),
              let data = Self.bundledFile(resource.name)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": resource.mimeType,
                "Content-Length": String(data.count),
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    // Xcode copies the files of a synchronized folder into the bundle's
    // Resources, flattened; the subdirectory is looked up too in case the
    // folder is ever added as a folder reference.
    private static func bundledFile(_ name: String) -> Data? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let url = Bundle.main.url(forResource: base, withExtension: ext)
            ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Workspace")
        return url.flatMap { try? Data(contentsOf: $0) }
    }
}
