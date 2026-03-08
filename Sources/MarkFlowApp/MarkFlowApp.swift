import SwiftUI

extension Notification.Name {
    static let markFlowPrintRequested = Notification.Name("MarkFlowPrintRequested")
}

@main
struct MarkFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    let openedTab = NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
                    if !openedTab {
                        NSDocumentController.shared.newDocument(nil)
                    }
                }
                .keyboardShortcut("t")
            }
            EditorCommandMenu()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func print(_ sender: Any?) {
        let targetWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        NotificationCenter.default.post(name: .markFlowPrintRequested, object: targetWindow)
    }

    @objc func printDocument(_ sender: Any?) {
        let targetWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        NotificationCenter.default.post(name: .markFlowPrintRequested, object: targetWindow)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    @objc private func handleDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard !(window is NSPanel) else { return }

        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MarkdownDocumentWindow"

        guard let target = NSApp.windows.first(where: { other in
            other != window &&
            !(other is NSPanel) &&
            other.isVisible &&
            other.tabbingIdentifier == window.tabbingIdentifier
        }) else {
            return
        }

        let alreadyTabbed = target.tabbedWindows?.contains(where: { $0 == window }) ?? false
        if !alreadyTabbed {
            target.addTabbedWindow(window, ordered: .above)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
