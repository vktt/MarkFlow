import AppKit
import Foundation
import MarkFlowEngine
import Testing

// WKWebView's web content process requires a GUI application environment.
// swift test runs as a CLI tool whose activation policy is .prohibited, meaning
// the web content XPC service cannot be bootstrapped and navigation delegates
// never fire — causing the test to hang. The trait below disables the test in
// that context while keeping it active under xcodebuild / Xcode's test runner,
// where a proper application host provides the required environment.
private let hasGUIContext = NSRunningApplication.current.activationPolicy != .prohibited

@Test(.enabled(if: hasGUIContext))
@MainActor
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
