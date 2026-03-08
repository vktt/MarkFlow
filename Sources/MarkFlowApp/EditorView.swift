import AppKit
import MarkFlowEngine
import SwiftUI

struct EditorView: View {
    @Binding var document: MarkdownDocument
    @StateObject private var viewModel: EditorViewModel
    @State private var showPreview = true
    @State private var splitViewIdentity = UUID()
    @State private var exporter = WebKitPDFExporter()
    @State private var sourceJumpRequest: SourceJumpRequest?
    @State private var previewJumpAnchor: String?

    init(document: Binding<MarkdownDocument>) {
        _document = document
        _viewModel = StateObject(wrappedValue: EditorViewModel(sourceText: document.wrappedValue.text))
    }

    var body: some View {
        HSplitView {
            SourceTextEditorView(
                text: Binding(
                get: { document.text },
                set: { newValue in
                    document.text = newValue
                    viewModel.updateSource(newValue)
                }
            ),
                jumpRequest: $sourceJumpRequest,
                onCommandClickLine: { line in
                    if let anchor = viewModel.previewAnchor(forSourceLine: line) {
                        previewJumpAnchor = anchor
                    }
                }
            )
            .background(Color(nsColor: NSColor(white: 0.95, alpha: 1.0)))
            .frame(minWidth: 320, maxWidth: .infinity)

            if showPreview {
                MarkdownPreviewWebView(
                    html: viewModel.renderedHTML,
                    jumpToAnchor: $previewJumpAnchor,
                    onCommandClickSourceLine: { line, clickYRatio in
                        sourceJumpRequest = SourceJumpRequest(
                            line: viewModel.sourceLine(forPreviewLine: line),
                            viewportFraction: clickYRatio
                        )
                    }
                )
                .background(Color.white)
                .frame(minWidth: 320, maxWidth: .infinity)
            }
        }
        .id(splitViewIdentity)
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    togglePreview()
                } label: {
                    Label(showPreview ? "Hide Preview" : "Show Preview", systemImage: "sidebar.right")
                }
                .help(showPreview ? "Hide Preview" : "Show Preview")

                Button {
                    printDocument()
                } label: {
                    Label("Print", systemImage: "printer")
                }

                Button {
                    Task { await exportPDF() }
                } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
            }
        }
        .onChange(of: document.text) { _, newText in
            if newText != viewModel.sourceText {
                viewModel.updateSource(newText)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .markFlowPrintRequested)) { _ in
            printDocument()
        }
        .alert("Export Error", isPresented: Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.lastError ?? "Unknown error")
        }
        .focusedSceneValue(
            \.editorActions,
            EditorActions(
                printDocument: { printDocument() },
                exportPDF: { Task { await exportPDF() } }
            )
        )
    }

    private var title: String {
        document.text
            .split(separator: "\n")
            .first
            .map(String.init) ?? "Markdown"
    }

    private func togglePreview() {
        let shouldShowPreview = !showPreview
        showPreview = shouldShowPreview

        // Rebuild split view when preview is restored so it defaults to an even split.
        if shouldShowPreview {
            splitViewIdentity = UUID()
        }
    }

    @MainActor
    private func exportPDF() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Document.pdf"

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            try await exporter.exportPDF(html: viewModel.renderedHTML, to: destination)
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }

    @MainActor
    private func printDocument() {
        Task { @MainActor in
            do {
                try await exporter.print(html: viewModel.renderedHTML)
            } catch {
                viewModel.setError(error.localizedDescription)
            }
        }
    }
}
