import Foundation
import MarkFlowEngine

struct PreviewBlockMapping: Sendable {
    let id: String
    let startLine: Int
    let endLine: Int
}

@MainActor
final class EditorViewModel: ObservableObject {
    private struct RenderedState: Sendable {
        let html: String
        let mappings: [PreviewBlockMapping]
        let diagnostics: [RenderDiagnostic]
    }

    @Published var sourceText: String
    @Published private(set) var renderedHTML: String = ""
    @Published private(set) var lastError: String?

    private let renderer: any MarkdownRenderer
    private let renderOptions: RenderOptions
    private var mappings: [PreviewBlockMapping] = []
    private var renderTask: Task<Void, Never>?
    private var renderVersion: UInt64 = 0
    private var lastRenderError: String?

    init(
        sourceText: String,
        renderer: any MarkdownRenderer = MarkdownItRenderer(),
        renderOptions: RenderOptions = RenderOptions()
    ) {
        self.sourceText = sourceText
        self.renderer = renderer
        self.renderOptions = renderOptions

        let initial = Self.renderedState(markdown: sourceText, renderer: renderer, options: renderOptions)
        renderedHTML = initial.html
        mappings = initial.mappings
        if let renderError = initial.diagnostics.first(where: { $0.severity == .error })?.message {
            lastRenderError = renderError
            lastError = renderError
        }
    }

    deinit {
        renderTask?.cancel()
    }

    func updateSource(_ text: String) {
        sourceText = text
        enqueueRender(for: text, debounce: true)
    }

    func sourceLine(forPreviewLine line: Int) -> Int {
        if let mapping = mappings.first(where: { line >= $0.startLine && line <= $0.endLine }) {
            return mapping.startLine
        }
        return line
    }

    func previewAnchor(forSourceLine line: Int) -> String? {
        if let exact = mappings.first(where: { line >= $0.startLine && line <= $0.endLine }) {
            return exact.id
        }
        return mappings.last(where: { $0.startLine <= line })?.id
    }

    func setError(_ message: String) {
        lastError = message
    }

    func clearError() {
        lastError = nil
    }

    private func enqueueRender(for text: String, debounce: Bool) {
        renderTask?.cancel()
        renderVersion &+= 1
        let version = renderVersion
        let renderer = self.renderer
        let options = self.renderOptions

        renderTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled else { return }

            let renderedState = await Task.detached(priority: .userInitiated) {
                Self.renderedState(markdown: text, renderer: renderer, options: options)
            }.value
            guard !Task.isCancelled else { return }

            self?.apply(renderedState, version: version)
        }
    }

    private func apply(_ renderedState: RenderedState, version: UInt64) {
        guard version == renderVersion else { return }
        renderedHTML = renderedState.html
        mappings = renderedState.mappings

        if let renderError = renderedState.diagnostics.first(where: { $0.severity == .error })?.message {
            lastRenderError = renderError
            lastError = renderError
        } else if let lastRenderError, lastError == lastRenderError {
            self.lastRenderError = nil
            lastError = nil
        }
    }

    nonisolated private static func renderedState(
        markdown: String,
        renderer: any MarkdownRenderer,
        options: RenderOptions
    ) -> RenderedState {
        let renderResult = renderer.render(markdown: markdown, options: options)
        let mappings = HTMLLineMappingExtractor.extract(from: renderResult.html)
        return RenderedState(
            html: renderResult.html,
            mappings: mappings,
            diagnostics: renderResult.diagnostics
        )
    }
}

enum HTMLLineMappingExtractor {
    private static let tagRegex = try! NSRegularExpression(pattern: #"<([a-zA-Z0-9]+)\s+[^>]*id="(src-map-[^"]+)"[^>]*>"#)
    private static let srcStartRegex = try! NSRegularExpression(pattern: #"data-src-start="(\d+)""#)
    private static let srcEndRegex = try! NSRegularExpression(pattern: #"data-src-end="(\d+)""#)

    static func extract(from html: String) -> [PreviewBlockMapping] {
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = tagRegex.matches(in: html, range: nsRange)
        var result: [PreviewBlockMapping] = []
        result.reserveCapacity(matches.count)

        for match in matches {
            guard let fullRange = Range(match.range, in: html),
                  let idRange = Range(match.range(at: 2), in: html)
            else { continue }

            let tag = String(html[fullRange])
            let id = String(html[idRange])
            let startLine = intMatch(regex: srcStartRegex, in: tag) ?? 0
            let endLine = intMatch(regex: srcEndRegex, in: tag) ?? startLine
            result.append(.init(id: id, startLine: startLine, endLine: endLine))
        }

        return result.sorted { lhs, rhs in
            if lhs.startLine == rhs.startLine {
                return lhs.endLine < rhs.endLine
            }
            return lhs.startLine < rhs.startLine
        }
    }

    private static func intMatch(regex: NSRegularExpression, in string: String) -> Int? {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let valueRange = Range(match.range(at: 1), in: string)
        else { return nil }
        return Int(string[valueRange])
    }
}
