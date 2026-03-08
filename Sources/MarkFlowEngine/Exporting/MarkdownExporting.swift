import Foundation

@MainActor
public protocol MarkdownExporting: Sendable {
    func exportPDF(html: String, to url: URL) async throws
    func print(html: String) async throws
}
