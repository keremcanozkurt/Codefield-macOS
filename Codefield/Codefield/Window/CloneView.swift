import AppKit
import SwiftUI

@Observable
final class CloneRequest {
    enum State: Equatable {
        case editing
        case cloning
        case failed(GitCloneFailure, detail: String?)
    }

    // Editing any field clears a previous failure, which described other input.
    var remote = "" {
        didSet {
            if !isNameEdited { name = GitRemote.defaultDirectoryName(remote) ?? "" }
            clearFailure()
        }
    }
    var name = "" {
        didSet { clearFailure() }
    }
    var isNameEdited = false
    var parent: URL? {
        didSet { clearFailure() }
    }
    var state = State.editing

    init(parent: URL?) {
        self.parent = parent
    }

    var remoteProblem: String? {
        remote.isEmpty ? nil : GitRemote.problem(with: remote)
    }

    var nameProblem: String? {
        name.isEmpty || CloneDestination.isValidName(name) ? nil : "Use a folder name without “/”."
    }

    var destination: URL? {
        guard let parent, CloneDestination.isValidName(name) else { return nil }
        return parent.appending(path: name, directoryHint: .isDirectory)
    }

    private func clearFailure() {
        if case .failed = state { state = .editing }
    }

    var canClone: Bool {
        state != .cloning && !remote.isEmpty && remoteProblem == nil && destination != nil
    }
}

struct CloneView: View {
    let model: RepositoryWindowModel
    @State private var request: CloneRequest
    @Environment(\.dismiss) private var dismiss
    @FocusState private var remoteFocused: Bool

    init(model: RepositoryWindowModel) {
        self.model = model
        _request = State(initialValue: CloneRequest(parent: model.cloneParent.url))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clone Git Repository")
                    .font(.system(size: 15, weight: .semibold))
                Text("Uses the Git and SSH setup already on your Mac. Codefield never asks for credentials.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            Field(label: "Remote", problem: request.remoteProblem) {
                TextField("", text: $request.remote, prompt: Text("git@example.com:team/project.git"))
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($remoteFocused)
                    .autocorrectionDisabled()
            }
            .disabled(isCloning)

            Field(label: "Clone into", problem: nil) {
                HStack(spacing: 8) {
                    Text(request.parent.map { RecentRepositoryStore.abbreviatingHome(RecentRepositoryStore.standardPath($0)) } ?? "No folder chosen")
                        .font(.system(size: 12))
                        .foregroundStyle(request.parent == nil ? Theme.subtle : Theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…", action: chooseParent)
                }
            }
            .disabled(isCloning)

            Field(label: "Folder name", problem: request.nameProblem) {
                TextField("", text: Binding(
                    get: { request.name },
                    set: {
                        request.name = $0
                        request.isNameEdited = true
                    }
                ), prompt: Text("project"))
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            }
            .disabled(isCloning)

            if let destination = request.destination {
                Text("Clones into \(RecentRepositoryStore.abbreviatingHome(RecentRepositoryStore.standardPath(destination)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if case let .failed(failure, detail) = request.state, failure != .cancelled {
                FailureView(failure: failure, detail: detail)
            }

            HStack {
                if isCloning {
                    ProgressView().controlSize(.small)
                    Text("Cloning…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Cancel") {
                    if isCloning { model.cancelClone() } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Clone & Open", action: clone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!request.canClone)
            }
        }
        .padding(20)
        .frame(width: 480)
        .interactiveDismissDisabled(isCloning)
        .onAppear { remoteFocused = true }
    }

    private var isCloning: Bool {
        request.state == .cloning
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder the clone goes into."
        panel.directoryURL = request.parent
        if panel.runModal() == .OK, let url = panel.url {
            request.parent = url
        }
    }

    private func clone() {
        guard request.canClone, let parent = request.parent else { return }
        request.state = .cloning
        Task {
            let outcome = await model.clone(remote: request.remote, parent: parent, name: request.name)
            if let failure = outcome.failure {
                request.state = .failed(failure, detail: outcome.detail)
            } else {
                dismiss()
            }
        }
    }
}

private struct Field<Content: View>: View {
    let label: String
    let problem: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            content
            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
            }
        }
    }
}

private struct FailureView: View {
    let failure: GitCloneFailure
    let detail: String?
    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(failure.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.danger)
            Text(failure.message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let output = trimmedDetail {
                Button {
                    showsDetail.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showsDetail ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 10)
                        Text("Git output")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showsDetail {
                    ScrollView {
                        Text(output)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.danger.opacity(0.3)))
    }

    // The last lines are the ones that explain the failure.
    private var trimmedDetail: String? {
        guard let detail else { return nil }
        let lines = detail.split(whereSeparator: \.isNewline).suffix(20)
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
