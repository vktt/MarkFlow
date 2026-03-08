@testable import MarkFlowApp
import Foundation
import MarkFlowEngine
import Testing

private struct StubRenderer: MarkdownRenderer {
    func render(markdown: String, options: RenderOptions) -> RenderResult {
        .init(html: "<p>\(markdown)</p>")
    }
}

@Test @MainActor
func viewModelRendersImmediately() {
    let vm = EditorViewModel(sourceText: "Hello", renderer: StubRenderer())
    #expect(vm.renderedHTML == "<p>Hello</p>")
}

@Test @MainActor
func viewModelStoresErrors() {
    let vm = EditorViewModel(sourceText: "", renderer: StubRenderer())
    vm.setError("boom")
    #expect(vm.lastError == "boom")
    vm.clearError()
    #expect(vm.lastError == nil)
}

@Test @MainActor
func mappingExtractorParsesLineRanges() {
    let html = """
    <main>
      <h1 id="src-map-0" data-src-start="0" data-src-end="0">Heading</h1>
      <p id="src-map-1" data-src-start="2" data-src-end="3">Body</p>
      <pre id="src-map-2" data-src-start="5" data-src-end="8"><code>x</code></pre>
    </main>
    """

    let mappings = HTMLLineMappingExtractor.extract(from: html)
    #expect(mappings.count == 3)
    #expect(mappings[0].id == "src-map-0")
    #expect(mappings[0].startLine == 0)
    #expect(mappings[1].startLine == 2)
    #expect(mappings[1].endLine == 3)
    #expect(mappings[2].startLine == 5)
    #expect(mappings[2].endLine == 8)
}

@Test @MainActor
func sourceAndPreviewLookupUseMappings() {
    struct MappingRenderer: MarkdownRenderer {
        func render(markdown: String, options: RenderOptions) -> RenderResult {
            .init(
                html: """
                <main>
                  <h1 id="src-map-0" data-src-start="0" data-src-end="0">A</h1>
                  <p id="src-map-1" data-src-start="2" data-src-end="4">B</p>
                </main>
                """
            )
        }
    }

    let vm = EditorViewModel(sourceText: "# A\n\nB", renderer: MappingRenderer())
    #expect(vm.sourceLine(forPreviewLine: 3) == 2)
    #expect(vm.previewAnchor(forSourceLine: 3) == "src-map-1")
    #expect(vm.previewAnchor(forSourceLine: 100) == "src-map-1")
}

@Test @MainActor
func viewModelSurfacesRendererErrors() {
    struct FailingRenderer: MarkdownRenderer {
        func render(markdown: String, options: RenderOptions) -> RenderResult {
            .init(
                html: "<pre><code>fallback</code></pre>",
                diagnostics: [.init(severity: .error, message: "Renderer failed to initialize.")]
            )
        }
    }

    let vm = EditorViewModel(sourceText: "Hello", renderer: FailingRenderer())
    #expect(vm.lastError == "Renderer failed to initialize.")
}

@Test
func previewSyncPayloadParsing() {
    let parsed = parsePreviewSyncPayload([
        "startLine": 12,
        "clickYRatio": NSNumber(value: 0.25)
    ])

    #expect(parsed?.startLine == 12)
    #expect(parsed?.clickYRatio == 0.25)

    let clamped = parsePreviewSyncPayload([
        "startLine": 8,
        "clickYRatio": NSNumber(value: 2.3)
    ])
    #expect(clamped?.clickYRatio == 1.0)

    #expect(parsePreviewSyncPayload(["clickYRatio": 0.5]) == nil)
}

@Test
func textDecodingRejectsBinaryData() {
    let data = Data([0x00, 0x01, 0x02, 0x03, 0x20, 0x41])
    #expect(TextDecoding.decode(data) == nil)
    #expect(TextDecoding.isProbablyBinary(data))
}

@Test
func textDecodingHandlesUtf16() {
    let source = "Hello markdown"
    let data = source.data(using: .utf16LittleEndian)!
    #expect(TextDecoding.decode(data) == source)
}

@Test
func sourceLineMapperRoundTrip() {
    let text = """
    line 0
    line 1
    line 2
    """
    let lineTwoRange = SourceLineMapper.characterRange(forLineNumber: 2, in: text)
    let resolvedLine = SourceLineMapper.lineNumber(forCharacterIndex: lineTwoRange.location, in: text)
    #expect(resolvedLine == 2)
}

@Test @MainActor
func appDelegatePrintActionsPostNotifications() {
    final class Observer: NSObject {
        var count = 0
        @objc func handleNotification(_ notification: Notification) {
            count += 1
        }
    }

    let observer = Observer()
    NotificationCenter.default.addObserver(
        observer,
        selector: #selector(Observer.handleNotification(_:)),
        name: .markFlowPrintRequested,
        object: nil
    )
    defer { NotificationCenter.default.removeObserver(observer) }

    let delegate = AppDelegate()
    delegate.print(nil)
    delegate.printDocument(nil)
    #expect(observer.count == 2)
}
