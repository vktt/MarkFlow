import Foundation
import MarkFlowEngine
import Testing

@Test @MainActor
func exporterWritesNonEmptyPDF() async throws {
    let exporter = WebKitPDFExporter()
    let destination = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")

    try await exporter.exportPDF(html: "<html><body><h1>Test</h1></body></html>", to: destination)
    let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
    let size = (attributes[.size] as? NSNumber)?.intValue ?? 0

    #expect(size > 0)
}
