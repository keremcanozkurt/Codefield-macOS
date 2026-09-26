# Codefield for macOS

Understand a local codebase visually, in a native Mac app.

Codefield for macOS opens a repository folder on your Mac, finds the relationships between its source files, and shows them in the same Graph and Structure workspace as [Codefield](https://github.com/keremcanozkurt/Codefield): search, filters, the file inspector, Impact Mode, Path Finder and PNG export. The source code stays on your Mac.

## Status

In development. The app builds and runs from Xcode; there is no signed or notarized release yet, and it has only been run on the developer's own Mac.

## How it is built

The window is SwiftUI. The workspace inside it is Codefield's own web interface, bundled into the app and shown in a `WKWebView`.

- **Swift** owns the file system: the open panel, drag and drop, recent repositories (security-scoped bookmarks), listing the folder and reading source files. It is the only part that touches the disk.
- **The page** runs Codefield's TypeScript analysis and draws the result. The analysis runs in a web worker inside the web view, so the app needs no Node.js, no local server and no network access.

An analysis goes like this:

1. Swift lists the folder without following symbolic links and without entering dependency or build directories, and sends the page the list of paths and sizes.
2. The page selects the source and configuration files with Codefield's own rules and asks for them.
3. Swift reads only those files, and only if they are in the listing: regular files inside the folder, opened without following links, at most 1 MiB each, valid UTF-8. The text goes to the page in batches.
4. The page runs the analyzers, builds the graph and shows it.

Swift and the page talk through two calls: `window.codefield.receive(message)`, which the app calls with `callAsyncJavaScript`, and the `codefield` script message handler. The messages are defined in `Codefield/Codefield/Bridge/BridgeMessages.swift` and `Web/src/bridge.ts`. Every analysis has a run number, and messages for an older run are ignored on both sides.

## Repository layout

```text
Codefield/                       Xcode project
  Codefield/
    Analysis/                    folder listing and file reading
    Bridge/                      web view, URL scheme handler, messages
    Repository/                  opening folders, recent repositories, Git details
    Window/                      windows, start screen, toolbar, menus
    Resources/Workspace/         the built workspace page (generated)
  CodefieldTests/
Web/
  upstream/                      Codefield's shared source, copied unchanged
  src/                           the page's host code and the analysis worker
  scripts/                       sync-upstream.mjs, build.mjs
```

`Web/upstream` is a copy of `src/lib`, `src/components` and `src/app/globals.css` from the Codefield repository, at the commit in `Web/upstream/REVISION`. It is not edited by hand. `Web/src` holds what differs on the Mac: the page that hosts the workspace, the analysis worker, the FAQ and error text.

## Building

Needs Xcode 27 and macOS 27. No Apple Developer account is needed to run it locally.

```bash
open Codefield/Codefield.xcodeproj
```

Choose the Codefield scheme and run. From the command line:

```bash
xcodebuild -project Codefield/Codefield.xcodeproj -scheme Codefield -configuration Debug build
xcodebuild -project Codefield/Codefield.xcodeproj -scheme Codefield test
```

The built workspace page is checked in, so Xcode does not need Node.js. After changing anything under `Web/`, rebuild it with Node.js 22.18 or later:

```bash
cd Web
npm install
npm run build      # writes Codefield/Codefield/Resources/Workspace
npm test           # Codefield's own tests, plus the macOS page and worker
npm run typecheck
```

To take newer shared code from Codefield, with the two repositories side by side:

```bash
cd Web
npm run sync       # copies from ../../Codefield, only reading it
npm run build
```

## Using it

Open a repository with Open Repository (⌘O), by dragging its folder onto the window, or from the recent list. Any folder works, Git repository or not. The window title shows the folder name, and the subtitle shows the branch and origin read from `.git`.

Analyze Again (⌘R) reads the folder again as it is on disk, after edits, pulls or branch switches; the view, selection and filters stay where they were, as far as the files still exist. Find File (⌘F) moves to the workspace search. One repository is open per window; File > New Window opens another.

## Privacy and security

- The app runs in the App Sandbox with read-only access to the folders you open, plus the Downloads folder for PNG exports. It also has the outgoing-network entitlement, because WebKit's networking process does not run in a sandboxed app without it, even for a page served from the app itself. Codefield makes no network requests of its own.
- The workspace page is served from the app bundle under a private URL scheme. It cannot navigate anywhere else, and its content security policy allows no remote scripts, styles, fonts or connections.
- The page never receives a path to open. It receives repository-relative paths and file contents that Swift has read, and Swift reads only files from its own listing of the opened folder.
- Repository code is never run. Git details come from reading `.git/HEAD` and `.git/config`, not from running `git`.
- Recent repositories are stored in the app's preferences as security-scoped bookmarks (how macOS remembers that you granted access to a folder), with the folder's name and when it was opened. No source code or credentials are stored.
- Links to the Codefield site open in your default browser.

## Limitations

- Everything listed under Limitations in the Codefield README applies: static analysis only, and relationships that exist only at runtime are not found.
- No clone from inside the app. Clone with Git, then open the folder.
- No file watching. Use Analyze Again.
- The Git branch is not shown when you open a subfolder of a repository: the sandbox does not allow reading the parent folders.
- The FAQ is available once a repository is open.

## License

Codefield for macOS is source-available under the PolyForm Noncommercial License 1.0.0, like Codefield itself. You can read, fork and modify it for personal and non-commercial use. Commercial use requires permission from Kerem Can Özkurt. See [LICENSE](LICENSE).

The workspace page bundles React, Sigma.js, Graphology and the TypeScript compiler. `npm run build` collects their license texts into `ThirdPartyLicenses.txt`, which ships in the app's resources.
