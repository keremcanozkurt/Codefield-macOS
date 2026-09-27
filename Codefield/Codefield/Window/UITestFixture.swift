#if DEBUG
import Foundation

// UI tests start the app with this argument to get a small repository without
// the open panel, which runs outside the app and cannot be driven by tests.
// The fixture lives in the app's own temporary folder, and recent
// repositories are kept apart from the real list.
enum UITestFixture {
    static let argument = "-CodefieldUITestFixture"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    // Only the first window opens it; windows opened later start empty.
    static var isOpened = false

    // app.ts → a.ts → b.ts → c.ts, an isolated lonely.ts, and a Python pair.
    static let files: [String: String] = [
        "src/app.ts": "import { a } from \"./a\";\nexport const app = a;\n",
        "src/a.ts": "import { b } from \"./b\";\nexport const a = b;\n",
        "src/b.ts": "import { c } from \"./c\";\nexport const b = c;\n",
        "src/c.ts": "export const c = 1;\n",
        "src/lonely.ts": "export const lonely = 1;\n",
        "tools/run.py": "import helper\n",
        "tools/helper.py": "VALUE = 1\n",
    ]

    static func create() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString)/demo", directoryHint: .isDirectory)
        for (path, content) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }
}

extension RepositoryWindowModel {
    func openUITestFixtureIfRequested() {
        guard UITestFixture.isActive, !UITestFixture.isOpened, let url = try? UITestFixture.create() else { return }
        UITestFixture.isOpened = true
        open(url)
    }
}
#endif
