import AppKit
import SwiftUI

struct SourceJumpRequest: Equatable {
    let line: Int
    let viewportFraction: CGFloat
}

struct SourceTextEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var jumpRequest: SourceJumpRequest?
    let onCommandClickLine: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommandClickLine: onCommandClickLine)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SourceNSTextView()
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.delegate = context.coordinator
        textView.commandClickHandler = { [weak coordinator = context.coordinator] index in
            coordinator?.handleCommandClick(characterIndex: index)
        }

        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.onCommandClickLine = onCommandClickLine

        if textView.string != text {
            textView.string = text
        }

        if let request = jumpRequest {
            context.coordinator.jumpTo(request: request)
            DispatchQueue.main.async {
                jumpRequest = nil
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var textView: NSTextView?
        var onCommandClickLine: (Int) -> Void

        init(text: Binding<String>, onCommandClickLine: @escaping (Int) -> Void) {
            _text = text
            self.onCommandClickLine = onCommandClickLine
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        @MainActor
        func handleCommandClick(characterIndex: Int) {
            guard let textView else { return }
            let line = SourceLineMapper.lineNumber(forCharacterIndex: characterIndex, in: textView.string)
            onCommandClickLine(line)
        }

        @MainActor
        func jumpTo(request: SourceJumpRequest) {
            guard let textView else { return }
            let targetLine = max(request.line, 0)
            let viewportFraction = min(max(request.viewportFraction, 0), 1)
            let range = SourceLineMapper.characterRange(forLineNumber: targetLine, in: textView.string)
            textView.setSelectedRange(range)

            guard let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else {
                textView.scrollRangeToVisible(range)
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            if glyphRect.isNull {
                textView.scrollRangeToVisible(range)
                return
            }

            let containerOrigin = textView.textContainerOrigin
            glyphRect.origin.x += containerOrigin.x
            glyphRect.origin.y += containerOrigin.y

            let clipView = scrollView.contentView
            let visibleHeight = clipView.bounds.height
            let documentHeight = textView.bounds.height
            let maxOriginY = max(0, documentHeight - visibleHeight)

            var targetOriginY = glyphRect.minY - (visibleHeight * viewportFraction)
            targetOriginY = min(max(targetOriginY, 0), maxOriginY)

            var nextOrigin = clipView.bounds.origin
            nextOrigin.y = targetOriginY
            clipView.setBoundsOrigin(nextOrigin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}

final class SourceNSTextView: NSTextView {
    var commandClickHandler: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let commandPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        if commandPressed {
            let localPoint = convert(event.locationInWindow, from: nil)
            if let index = characterIndexForCommandClick(at: localPoint) {
                commandClickHandler?(index)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func characterIndexForCommandClick(at point: NSPoint) -> Int? {
        let insertionIndex = characterIndexForInsertion(at: point)
        if insertionIndex != NSNotFound {
            return insertionIndex
        }

        guard let layoutManager, let textContainer else { return nil }
        let containerOrigin = textContainerOrigin
        let inContainer = NSPoint(x: point.x - containerOrigin.x, y: point.y - containerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: inContainer, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

enum SourceLineMapper {
    static func lineNumber(forCharacterIndex index: Int, in text: String) -> Int {
        let bounded = min(max(index, 0), text.utf16.count)
        var line = 0
        var i = 0
        for codeUnit in text.utf16 {
            if i >= bounded { break }
            if codeUnit == 10 {
                line += 1
            }
            i += 1
        }
        return line
    }

    static func characterRange(forLineNumber line: Int, in text: String) -> NSRange {
        if line <= 0 {
            return NSRange(location: 0, length: 0)
        }

        let utf16 = text.utf16
        var currentLine = 0
        var location = 0

        for scalar in utf16 {
            if currentLine == line { break }
            location += 1
            if scalar == 10 {
                currentLine += 1
            }
        }

        let clamped = min(location, utf16.count)
        return NSRange(location: clamped, length: 0)
    }
}
