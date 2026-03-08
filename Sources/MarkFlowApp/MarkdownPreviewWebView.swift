import SwiftUI
import WebKit

struct PreviewSyncPayload: Equatable {
    let startLine: Int
    let clickYRatio: CGFloat
}

func parsePreviewSyncPayload(_ body: Any) -> PreviewSyncPayload? {
    guard let dict = body as? [String: Any],
          let startLine = dict["startLine"] as? Int
    else { return nil }

    let clickYRatio = (dict["clickYRatio"] as? NSNumber)?.doubleValue ?? 0.5
    let clamped = CGFloat(min(max(clickYRatio, 0), 1))
    return PreviewSyncPayload(startLine: startLine, clickYRatio: clamped)
}

struct MarkdownPreviewWebView: NSViewRepresentable {
    let html: String
    @Binding var jumpToAnchor: String?
    let onCommandClickSourceLine: (Int, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommandClickSourceLine: onCommandClickSourceLine)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "previewSync")
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "previewSync")
        config.userContentController.addUserScript(.init(
            source: """
            document.addEventListener('click', function(event) {
              if (!event.metaKey) { return; }
              const node = event.target;
              if (!node) { return; }
              const element = node instanceof Element ? node : node.parentElement;
              if (!element) { return; }
              const mapped = element.closest('[data-src-start]');
              if (!mapped) { return; }
              const startLine = Number(mapped.getAttribute('data-src-start'));
              if (!Number.isFinite(startLine)) { return; }
              const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 1;
              const clickYRatio = Math.max(0, Math.min(1, event.clientY / viewportHeight));
              event.preventDefault();
              window.webkit.messageHandlers.previewSync.postMessage({ startLine: startLine, clickYRatio: clickYRatio });
            }, true);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = .clear
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }

        if let anchor = jumpToAnchor {
            context.coordinator.requestJump(to: anchor, in: webView)
            DispatchQueue.main.async {
                jumpToAnchor = nil
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String?
        private var pendingAnchor: String?
        private let onCommandClickSourceLine: (Int, CGFloat) -> Void

        init(onCommandClickSourceLine: @escaping (Int, CGFloat) -> Void) {
            self.onCommandClickSourceLine = onCommandClickSourceLine
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if let lastHTML {
                webView.loadHTMLString(lastHTML, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let pendingAnchor else { return }
            self.pendingAnchor = nil
            jump(to: pendingAnchor, in: webView)
        }

        func requestJump(to anchor: String, in webView: WKWebView) {
            if webView.isLoading {
                pendingAnchor = anchor
                return
            }
            jump(to: anchor, in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "previewSync",
                  let payload = parsePreviewSyncPayload(message.body)
            else { return }

            onCommandClickSourceLine(payload.startLine, payload.clickYRatio)
        }

        private func jump(to anchor: String, in webView: WKWebView) {
            let escaped = anchor
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            let js = """
            (function() {
              var el = document.getElementById('\(escaped)');
              if (!el) { return; }
              el.scrollIntoView({ behavior: 'auto', block: 'center' });
              el.classList.add('sync-target');
              setTimeout(function() { el.classList.remove('sync-target'); }, 700);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
