import AppKit
import Foundation
import PDFKit
import WebKit

public enum MarkdownExportError: Error {
    case webContentLoadFailed
    case htmlLoadTimedOut(seconds: TimeInterval)
}

extension MarkdownExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .webContentLoadFailed:
            return "Unable to load preview content for export."
        case let .htmlLoadTimedOut(seconds):
            return "Preview load timed out after \(Int(seconds)) seconds."
        }
    }
}

@MainActor
public final class WebKitPDFExporter: NSObject, MarkdownExporting {
    private static let htmlLoadTimeoutSeconds: TimeInterval = 20

    private var offscreenWebView: WKWebView?
    private var loadingDelegate: HTMLLoadDelegate?

    public override init() {
        super.init()
    }

    public func exportPDF(html: String, to url: URL) async throws {
        let data = try await renderPDFData(from: html)
        try data.write(to: url, options: .atomic)
    }

    public func print(html: String) async throws {
        let data = try await renderPDFData(from: html)
        guard let document = PDFDocument(data: data),
              let operation = document.printOperation(
                for: NSPrintInfo.shared,
                scalingMode: .pageScaleToFit,
                autoRotate: true
              ) else {
            throw MarkdownExportError.webContentLoadFailed
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    private func renderPDFData(from html: String) async throws -> Data {
        do {
            return try await renderPDFDataAttempt(from: html)
        } catch {
            // Recreate the backing WKWebView and retry once to recover from
            // occasional web content process crashes.
            offscreenWebView = nil
            return try await renderPDFDataAttempt(from: html)
        }
    }

    private func renderPDFDataAttempt(from html: String) async throws -> Data {
        let renderView = try await renderedWebView(for: html)
        await renderView.waitForStableLayout()
        return try await renderView.pdfData()
    }

    private func renderedWebView(for html: String) async throws -> WKWebView {
        let webView = offscreenWebView ?? makeOffscreenWebView()
        offscreenWebView = webView
        try await loadHTML(html, in: webView)
        return webView
    }

    private func makeOffscreenWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        return WKWebView(
            frame: CGRect(x: 0, y: 0, width: 900, height: 1200),
            configuration: configuration
        )
    }

    private func loadHTML(_ html: String, in webView: WKWebView) async throws {
        let delegate = HTMLLoadDelegate()
        loadingDelegate = delegate
        webView.navigationDelegate = delegate
        defer {
            webView.navigationDelegate = nil
            loadingDelegate = nil
        }

        try await delegate.load(
            html: html,
            in: webView,
            timeoutSeconds: Self.htmlLoadTimeoutSeconds
        )
    }
}

private extension WKWebView {
    @MainActor
    func waitForStableLayout() async {
        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
            callAsyncJavaScript(
                "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))",
                arguments: [:],
                in: nil,
                in: .defaultClient
            ) { result in
                Task { @MainActor in
                    continuation.resume(with: result)
                }
            }
        }
    }

    @MainActor
    func pdfData() async throws -> Data {
        let pageHeight = await contentHeight()
        let pageRect = CGRect(
            x: 0,
            y: 0,
            width: max(bounds.width, 900),
            height: max(pageHeight, 1200)
        )

        return try await withCheckedThrowingContinuation { continuation in
            let configuration = WKPDFConfiguration()
            configuration.rect = pageRect
            createPDF(configuration: configuration) { result in
                continuation.resume(with: result)
            }
        }
    }

    @MainActor
    func contentHeight() async -> CGFloat {
        do {
            let height = try await evaluateHeight()
            return CGFloat(height)
        } catch {
            return bounds.height
        }
    }

    @MainActor
    func evaluateHeight() async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let number = value as? NSNumber {
                    continuation.resume(returning: number.doubleValue)
                } else if let doubleValue = value as? Double {
                    continuation.resume(returning: doubleValue)
                } else {
                    continuation.resume(returning: Double(self.bounds.height))
                }
            }
        }
    }

}

@MainActor
private final class HTMLLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var hasResumed = false
    private var timeoutTask: Task<Void, Never>?

    func load(html: String, in webView: WKWebView, timeoutSeconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            hasResumed = false
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self, weak webView] in
                let nanoseconds = UInt64(max(timeoutSeconds, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    webView?.stopLoading()
                    self?.resume(with: .failure(MarkdownExportError.htmlLoadTimedOut(seconds: timeoutSeconds)))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume(with: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume(with: .failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        resume(with: .failure(MarkdownExportError.webContentLoadFailed))
    }

    private func resume(with result: Result<Void, Error>) {
        guard !hasResumed, let continuation else { return }
        hasResumed = true
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        switch result {
        case .success:
            continuation.resume(returning: ())
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
