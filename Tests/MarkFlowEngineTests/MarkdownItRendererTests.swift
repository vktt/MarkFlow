import MarkFlowEngine
import Testing

@Test func renderWrapsHTMLDocument() {
    let renderer = MarkdownItRenderer()
    let html = renderer.renderHTML(markdown: "# Title", options: .init())

    #expect(html.contains("<!doctype html>"))
    #expect(html.contains("<h1"))
    #expect(html.contains(">Title</h1>"))
    #expect(html.contains("data-src-start=\"0\""))
    #expect(html.contains("id=\"preview\""))
}

@Test func sanitizerRemovesControlChars() {
    let renderer = MarkdownItRenderer()
    let input = "hello\u{0000}world"
    let html = renderer.renderHTML(markdown: input, options: .init())

    #expect(!html.contains("\\u0000"))
    #expect(html.contains("hello"))
    #expect(html.contains("world"))
}

@Test func renderIncludesOptionsPayload() {
    let renderer = MarkdownItRenderer()
    let options = RenderOptions(theme: .dark, syntaxHighlighting: false, softWrap: false, smartTypography: false)
    let html = renderer.renderHTML(markdown: "text", options: options)

    #expect(html.contains("data-theme=\"dark\""))
    #expect(html.contains("data-syntax-highlighting=\"false\""))
    #expect(html.contains("data-soft-wrap=\"false\""))
    #expect(html.contains("<p"))
    #expect(html.contains(">text</p>"))
}

@Test func syntaxHighlightingOptionControlsFenceLanguageClass() {
    let renderer = MarkdownItRenderer()
    let markdown = """
    ```swift
    let x = 1
    ```
    """

    let highlighted = renderer.renderHTML(
        markdown: markdown,
        options: .init(syntaxHighlighting: true)
    )
    let plain = renderer.renderHTML(
        markdown: markdown,
        options: .init(syntaxHighlighting: false)
    )

    #expect(highlighted.contains("class=\"language-swift\""))
    #expect(!plain.contains("class=\"language-swift\""))
}

@Test func mappingGeneratedForCommonBlockTypes() {
    let renderer = MarkdownItRenderer()
    let markdown = """
    # Heading

    Paragraph text.

    - one
    - two

    > block quote

    | a | b |
    | - | - |
    | 1 | 2 |

    ```swift
    print("ok")
    ```
    """

    let html = renderer.renderHTML(markdown: markdown, options: .init())
    #expect(html.contains("<h1 id=\"src-map-"))
    #expect(html.contains("<p id=\"src-map-"))
    #expect(html.contains("<ul id=\"src-map-"))
    #expect(html.contains("<blockquote id=\"src-map-"))
    #expect(html.contains("<table id=\"src-map-"))
    #expect(html.contains("<pre id=\"src-map-"))
}

@Test func rendererProducesNoDiagnosticsForHappyPath() {
    let renderer = MarkdownItRenderer()
    let result = renderer.render(markdown: "# ok", options: .init())

    #expect(result.diagnostics.isEmpty)
    #expect(result.html.contains("<h1"))
}
