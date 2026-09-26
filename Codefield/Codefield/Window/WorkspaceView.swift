import AppKit
import SwiftUI

struct WorkspaceView: View {
    let model: RepositoryWindowModel

    var body: some View {
        ZStack {
            Theme.background
            // Kept in the hierarchy while hidden, so the page stays loaded and
            // keeps drawing frames during the first analysis.
            WorkspacePageView(view: model.web.view)
                .opacity(model.isRevealed ? 1 : 0)
                .accessibilityHidden(!model.isRevealed)
            if !model.isRevealed {
                AnalysisStatusView(progress: model.progress, failure: model.failure) {
                    model.analyzeAgain()
                }
            }
        }
    }
}

private struct WorkspacePageView: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ view: NSView, context: Context) {}
}

private struct AnalysisStatusView: View {
    let progress: AnalysisProgress?
    let failure: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let failure {
                Text("Analysis failed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Text(failure)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button("Analyze Again", action: retry)
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 4)
            } else if let progress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 4)
                Text(progress.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                // Reserved even when empty, so the label does not move.
                Text(progress.detail ?? " ")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.subtle)
            }
        }
        .frame(maxWidth: 420)
        .accessibilityElement(children: .combine)
    }
}
