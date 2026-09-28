import AppKit
import SwiftUI

struct WorkspaceView: View {
    let model: RepositoryWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .overlay(alignment: .bottom) {
            if let notice = model.exportNotice {
                ExportNoticeView(notice: notice) { model.revealExport(notice) }
                    // Clears the page's status line.
                    .padding(.bottom, 44)
                    .transition(.opacity)
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(5))
                        model.dismissExportNotice(notice)
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.exportNotice?.id)
    }
}

private struct ExportNoticeView: View {
    let notice: ExportNotice
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved to \(notice.folderPath)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.foreground)
                Text(notice.fileName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Show in Finder", action: reveal)
                .buttonStyle(QuietButtonStyle(secondary: true))
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.lineStrong))
        .onAppear {
            AccessibilityNotification.Announcement("Saved \(notice.fileName) to \(notice.folderPath)").post()
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
