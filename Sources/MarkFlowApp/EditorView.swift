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
    @State private var hostingWindow: NSWindow?

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
        .background(HostingWindowAccessor(window: $hostingWindow))
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
        .onReceive(NotificationCenter.default.publisher(for: .markFlowPrintRequested)) { notification in
            guard let targetWindow = notification.object as? NSWindow,
                  let hostingWindow,
                  targetWindow == hostingWindow else {
                return
            }
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
        let firstLine = String(document.text.prefix(while: { $0 != "\n" }))
        if let headingTitle = parsedHeadingTitle(from: firstLine), !headingTitle.isEmpty {
            return headingTitle
        }
        return firstLine.isEmpty ? "Markdown" : firstLine
    }

    private func parsedHeadingTitle(from line: String) -> String? {
        var index = line.startIndex
        var leadingSpaces = 0

        while index < line.endIndex, line[index] == " ", leadingSpaces < 4 {
            leadingSpaces += 1
            index = line.index(after: index)
        }

        guard leadingSpaces <= 3 else { return nil }

        var hashCount = 0
        while index < line.endIndex, line[index] == "#", hashCount < 7 {
            hashCount += 1
            index = line.index(after: index)
        }

        guard (1...6).contains(hashCount) else { return nil }
        guard index == line.endIndex || line[index] == " " || line[index] == "\t" else { return nil }

        var headingText = String(line[index...]).trimmingCharacters(in: .whitespaces)
        while headingText.last == "#" {
            headingText.removeLast()
        }
        headingText = headingText.trimmingCharacters(in: .whitespaces)
        return headingText.isEmpty ? nil : headingText
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

private struct HostingWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window?.windowNumber != nsView.window?.windowNumber {
            window = nsView.window
        }
    }
}
