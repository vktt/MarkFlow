import AppKit
import SwiftUI

struct WindowTabbingConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "MarkdownDocumentWindow"
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MarkdownDocumentWindow"
    }
}
