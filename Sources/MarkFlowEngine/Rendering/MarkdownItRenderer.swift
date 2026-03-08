import Foundation
import CoreText
import JavaScriptCore

public struct MarkdownItRenderer: MarkdownRenderer {
    public init() {}

    public func render(markdown: String, options: RenderOptions) -> RenderResult {
        FontRegistrar.registerBundledFontsIfNeeded()
        let assets = EmbeddedAssets.shared
        var diagnostics = assets.diagnostics
        let sanitizedMarkdown = MarkdownSanitizer.sanitize(markdown)

        let renderedMarkdown: String
        if assets.markdownItJS.isEmpty {
            diagnostics.append(.init(
                severity: .error,
                message: "Bundled markdown-it resource is unavailable. Rendering fallback plain text preview."
            ))
            renderedMarkdown = "<pre><code>\(HTMLEscaper.escape(sanitizedMarkdown))</code></pre>"
        } else {
            switch MarkdownItRuntime.shared.render(
                markdown: sanitizedMarkdown,
                options: options,
                markdownItJS: assets.markdownItJS
            ) {
            case let .success(value):
                if value.isEmpty && !sanitizedMarkdown.isEmpty {
                    diagnostics.append(.init(
                        severity: .warning,
                        message: "Renderer returned empty output. Showing plain text fallback."
                    ))
                    renderedMarkdown = "<pre><code>\(HTMLEscaper.escape(sanitizedMarkdown))</code></pre>"
                } else {
                    renderedMarkdown = value
                }
            case let .failure(error):
                diagnostics.append(.init(
                    severity: .error,
                    message: "Markdown render failed: \(error.localizedDescription). Showing plain text fallback."
                ))
                renderedMarkdown = "<pre><code>\(HTMLEscaper.escape(sanitizedMarkdown))</code></pre>"
            }
        }

        let html = htmlDocument(
            renderedMarkdown: renderedMarkdown,
            options: options,
            previewCSS: assets.previewCSS
        )
        return RenderResult(html: html, diagnostics: diagnostics)
    }

    private func htmlDocument(renderedMarkdown: String, options: RenderOptions, previewCSS: String) -> String {
        """
        <!doctype html>
        <html>
          <head>
            <meta charset=\"utf-8\">
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
            <style>\(previewCSS)</style>
          </head>
          <body data-theme=\"\(options.theme.rawValue)\" data-soft-wrap=\"\(options.softWrap)\" data-syntax-highlighting=\"\(options.syntaxHighlighting)\">
            <main id=\"preview\" class=\"markdown-body\">\(renderedMarkdown)</main>
          </body>
        </html>
        """
    }
}

private final class MarkdownItRuntime: @unchecked Sendable {
    static let shared = MarkdownItRuntime()

    private struct RuntimeState {
        let context: JSContext
        let renderFunction: JSValue
    }

    private let queue = DispatchQueue(label: "com.vikrant.markflow.markdown-it-runtime")
    private var state: RuntimeState?

    private init() {
    }

    func render(markdown: String, options: RenderOptions, markdownItJS: String) -> Result<String, MarkdownItRuntimeError> {
        queue.sync {
            do {
                let runtime = try ensureRuntime(markdownItJS: markdownItJS)
                runtime.context.exception = nil
                guard let rendered = runtime.renderFunction.call(
                    withArguments: [markdown, options.smartTypography, options.syntaxHighlighting]
                )?.toString() else {
                    return .failure(.functionCallFailed)
                }
                if let jsError = runtime.context.exception?.toString(), !jsError.isEmpty {
                    runtime.context.exception = nil
                    return .failure(.javaScriptException(jsError))
                }
                return .success(rendered)
            } catch let error as MarkdownItRuntimeError {
                return .failure(error)
            } catch {
                return .failure(.runtimeSetupFailed(error.localizedDescription))
            }
        }
    }

    private func ensureRuntime(markdownItJS: String) throws -> RuntimeState {
        if let state {
            return state
        }

        guard !markdownItJS.isEmpty else {
            throw MarkdownItRuntimeError.missingLibrary
        }
        guard let context = JSContext() else {
            throw MarkdownItRuntimeError.runtimeSetupFailed("Unable to create JavaScript context.")
        }

        context.exceptionHandler = { _, _ in }
        context.evaluateScript("var global = this; var window = this; var self = this;")
        context.evaluateScript(markdownItJS)
        context.evaluateScript(
            """
            var __mf_md = null;
            var __mf_typographer = null;
            var __mf_mapIndex = 0;
            var __mf_syntaxHighlighting = false;

            function __mf_ensure_md(typographer) {
              if (__mf_md !== null && __mf_typographer === typographer) { return; }
              if (typeof markdownit !== 'function') { return; }
              __mf_typographer = typographer;
              __mf_md = markdownit({
                html: false,
                linkify: true,
                breaks: false,
                typographer: typographer
              });
              const originalRenderToken = __mf_md.renderer.renderToken.bind(__mf_md.renderer);
              __mf_md.renderer.renderToken = function(tokens, idx, options, env, self) {
                const token = tokens[idx];
                if (token && token.nesting === 1 && token.block && Array.isArray(token.map)) {
                  const startLine = token.map[0];
                  const endLine = Math.max(token.map[1] - 1, startLine);
                  token.attrSet('id', 'src-map-' + __mf_mapIndex);
                  token.attrSet('data-src-start', String(startLine));
                  token.attrSet('data-src-end', String(endLine));
                  __mf_mapIndex += 1;
                }
                return originalRenderToken(tokens, idx, options, env, self);
              };
              __mf_md.renderer.rules.fence = function(tokens, idx, options, env, self) {
                const token = tokens[idx];
                const info = token.info ? __mf_md.utils.unescapeAll(token.info).trim() : '';
                const langName = info ? info.split(/\\s+/g)[0] : '';
                const langPrefix = options && options.langPrefix ? options.langPrefix : 'language-';
                const languageClass = __mf_syntaxHighlighting && langName
                  ? ' class="' + langPrefix + __mf_md.utils.escapeHtml(langName) + '"'
                  : '';
                let attrs = '';
                if (token.block && Array.isArray(token.map)) {
                  const startLine = token.map[0];
                  const endLine = Math.max(token.map[1] - 1, startLine);
                  attrs += ' id="src-map-' + __mf_mapIndex + '"';
                  attrs += ' data-src-start="' + String(startLine) + '"';
                  attrs += ' data-src-end="' + String(endLine) + '"';
                  __mf_mapIndex += 1;
                }
                return '<pre' + attrs + '><code' + languageClass + '>' + __mf_md.utils.escapeHtml(token.content) + '</code></pre>\\n';
              };
            }

            function __render_markdown(source, typographer, syntaxHighlighting) {
              if (typeof markdownit !== 'function') { return ''; }
              const useTypographer = !!typographer;
              __mf_syntaxHighlighting = !!syntaxHighlighting;
              __mf_ensure_md(useTypographer);
              if (__mf_md === null) { return ''; }
              __mf_mapIndex = 0;
              return __mf_md.render(source);
            }
            """
        )

        if let jsError = context.exception?.toString(), !jsError.isEmpty {
            throw MarkdownItRuntimeError.runtimeSetupFailed(jsError)
        }

        guard let renderFunction = context.objectForKeyedSubscript("__render_markdown") else {
            throw MarkdownItRuntimeError.functionUnavailable
        }

        let state = RuntimeState(context: context, renderFunction: renderFunction)
        self.state = state
        return state
    }
}

private enum MarkdownItRuntimeError: LocalizedError {
    case missingLibrary
    case runtimeSetupFailed(String)
    case functionUnavailable
    case functionCallFailed
    case javaScriptException(String)

    var errorDescription: String? {
        switch self {
        case .missingLibrary:
            return "Bundled markdown-it JavaScript is missing."
        case let .runtimeSetupFailed(details):
            return "Failed to initialize markdown runtime (\(details))."
        case .functionUnavailable:
            return "Markdown render function is unavailable."
        case .functionCallFailed:
            return "Markdown render function call failed."
        case let .javaScriptException(details):
            return "JavaScript exception during markdown render (\(details))."
        }
    }
}

struct LoadedAssets {
    let markdownItJS: String
    let previewCSS: String
    let diagnostics: [RenderDiagnostic]
}

enum EmbeddedAssets {
    static let shared: LoadedAssets = {
        var diagnostics: [RenderDiagnostic] = []

        let markdownItJS: String
        do {
            markdownItJS = try ResourceLoader.loadText(named: "markdown-it.min", ext: "js")
        } catch {
            markdownItJS = ""
            diagnostics.append(.init(
                severity: .error,
                message: "Unable to load bundled markdown-it JS resource (\(error.localizedDescription))."
            ))
        }

        let previewCSS: String
        do {
            previewCSS = try ResourceLoader.loadText(named: "preview", ext: "css")
        } catch {
            previewCSS = ""
            diagnostics.append(.init(
                severity: .warning,
                message: "Unable to load bundled preview CSS resource (\(error.localizedDescription))."
            ))
        }

        return LoadedAssets(
            markdownItJS: markdownItJS,
            previewCSS: previewCSS,
            diagnostics: diagnostics
        )
    }()
}

private enum ResourceLoaderError: LocalizedError {
    case missingResource(name: String, ext: String)
    case unreadableResource(name: String, ext: String)
    case invalidUTF8(name: String, ext: String)

    var errorDescription: String? {
        switch self {
        case let .missingResource(name, ext):
            return "Missing resource \(name).\(ext)"
        case let .unreadableResource(name, ext):
            return "Unable to read resource \(name).\(ext)"
        case let .invalidUTF8(name, ext):
            return "Resource \(name).\(ext) is not valid UTF-8"
        }
    }
}

enum ResourceLoader {
    static func loadText(named name: String, ext: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw ResourceLoaderError.missingResource(name: name, ext: ext)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw ResourceLoaderError.unreadableResource(name: name, ext: ext)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ResourceLoaderError.invalidUTF8(name: name, ext: ext)
        }
        return text
    }
}

enum MarkdownSanitizer {
    static func sanitize(_ markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let scalarFiltered = normalized.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x202A...0x202E:
                return false
            default:
                return true
            }
        }
        return String(String.UnicodeScalarView(scalarFiltered))
    }
}

enum HTMLEscaper {
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

enum FontRegistrar {
    static func registerBundledFontsIfNeeded() {
        _ = registerOnce
    }

    private static let registerOnce: Void = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "fonts") else {
            return ()
        }

        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
