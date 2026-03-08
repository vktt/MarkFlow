import Foundation

public struct RenderDiagnostic: Sendable, Equatable {
    public enum Severity: String, Sendable {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

public struct RenderResult: Sendable, Equatable {
    public let html: String
    public let diagnostics: [RenderDiagnostic]

    public init(html: String, diagnostics: [RenderDiagnostic] = []) {
        self.html = html
        self.diagnostics = diagnostics
    }
}

public protocol MarkdownRenderer: Sendable {
    func render(markdown: String, options: RenderOptions) -> RenderResult
}

public extension MarkdownRenderer {
    func renderHTML(markdown: String, options: RenderOptions) -> String {
        render(markdown: markdown, options: options).html
    }
}
