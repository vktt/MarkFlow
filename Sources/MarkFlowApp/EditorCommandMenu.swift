import AppKit
import SwiftUI

struct EditorActions {
    let printDocument: () -> Void
    let exportPDF: () -> Void
}

private struct EditorActionsKey: FocusedValueKey {
    typealias Value = EditorActions
}

extension FocusedValues {
    var editorActions: EditorActions? {
        get { self[EditorActionsKey.self] }
        set { self[EditorActionsKey.self] = newValue }
    }
}

struct EditorCommandMenu: Commands {
    @FocusedValue(\.editorActions) private var editorActions

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                if let action = editorActions {
                    action.printDocument()
                } else {
                    NSSound.beep()
                }
            }
            .keyboardShortcut("p")
        }

        CommandGroup(after: .printItem) {
            Divider()
            Button("Export as PDF...") {
                editorActions?.exportPDF()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(editorActions == nil)
        }
    }
}
