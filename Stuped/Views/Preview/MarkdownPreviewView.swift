import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let text: String
    let previewType: PreviewType
    var fileURL: URL?

    private var baseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(previewType: previewType)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.currentBaseURL = baseURL

        let html = Self.buildHTML(text: text, previewType: previewType)
        context.coordinator.loadHTMLWithFileAccess(html, baseURL: baseURL, into: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentBaseURL != baseURL {
            // File moved to a different directory — full page reload needed
            context.coordinator.currentBaseURL = baseURL
            context.coordinator.pageLoaded = false
            let html = Self.buildHTML(text: text, previewType: previewType)
            context.coordinator.loadHTMLWithFileAccess(html, baseURL: baseURL, into: webView)
            return
        }
        context.coordinator.pendingText = text
        context.coordinator.scheduleRender()
    }

    // MARK: - HTML Builder

    private static func buildHTML(text: String, previewType: PreviewType) -> String {
        switch previewType {
        case .markdown:
            return buildMarkdownHTML(text)
        case .html:
            return buildRawHTML(text)
        case .image:
            return ""
        }
    }

    private static func buildMarkdownHTML(_ markdown: String) -> String {
        let escaped = escapeForJS(markdown)

        let mdItJS = loadResource("markdown-it.min", ext: "js")
        let hljsJS = loadResource("highlight.min", ext: "js")
        let mermaidURL = resourceURL("mermaid.min", ext: "js")
        let previewCSS = loadResource("preview-styles", ext: "css")
        let hljsLightCSS = loadResource("hljs-github", ext: "css")
        let hljsDarkCSS = loadResource("hljs-github-dark", ext: "css")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>\(previewCSS)</style>
            <style>\(hljsLightCSS)</style>
            <style media="(prefers-color-scheme: dark)">\(hljsDarkCSS)</style>
            <script>\(mdItJS)</script>
            <script>\(hljsJS)</script>
        </head>
        <body>
            <div id="content"></div>
            <script src="\(mermaidURL)"></script>
            <script>
                const md = markdownit({
                    html: true,
                    linkify: true,
                    typographer: true,
                    highlight: function(str, lang) {
                        if (lang === 'mermaid') {
                            return '<pre class="mermaid">' + md.utils.escapeHtml(str) + '</pre>';
                        }
                        if (lang && hljs.getLanguage(lang)) {
                            try {
                                return '<pre class="hljs"><code>' +
                                       hljs.highlight(str, { language: lang, ignoreIllegals: true }).value +
                                       '</code></pre>';
                            } catch (_) {}
                        }
                        return '<pre class="hljs"><code>' + md.utils.escapeHtml(str) + '</code></pre>';
                    }
                });

                mermaid.initialize({
                    startOnLoad: false,
                    theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
                    securityLevel: 'loose'
                });

                window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function(e) {
                    mermaid.initialize({ startOnLoad: false, theme: e.matches ? 'dark' : 'default', securityLevel: 'loose' });
                    if (window._lastMarkdown) { renderMarkdown(window._lastMarkdown); }
                });

                let mermaidCounter = 0;

                async function renderMarkdown(text) {
                    window._lastMarkdown = text;
                    const scrollY = window.scrollY;
                    document.getElementById('content').innerHTML = md.render(text);

                    const els = document.querySelectorAll('pre.mermaid');
                    for (const el of els) {
                        const def = el.textContent;
                        const id = 'mermaid-' + (mermaidCounter++);
                        try {
                            const { svg } = await mermaid.render(id, def);
                            el.innerHTML = svg;
                            el.classList.add('mermaid-rendered');
                        } catch (e) {
                            el.innerHTML = '<div class="mermaid-error">' + e.message + '</div>';
                        }
                    }
                    window.scrollTo(0, scrollY);
                }

                renderMarkdown(`\(escaped)`);
            </script>
        </body>
        </html>
        """
    }

    private static func buildRawHTML(_ html: String) -> String {
        let escaped = escapeForJS(html)
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body>
            <div id="content">\(html)</div>
            <script>
                function updateContent(newHTML) {
                    document.getElementById('content').innerHTML = newHTML;
                }
                // Store initial content for consistency with markdown path
                updateContent(`\(escaped)`);
            </script>
        </body>
        </html>
        """
    }

    static func escapeForJS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func loadResource(_ name: String, ext: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return ""
    }

    private static func resourceURL(_ name: String, ext: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
            return url.absoluteString
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url.absoluteString
        }
        return ""
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var pendingText: String?
        var previewType: PreviewType
        var currentBaseURL: URL?
        private var renderWorkItem: DispatchWorkItem?
        var pageLoaded = false

        let tempFileURL: URL

        init(previewType: PreviewType) {
            self.previewType = previewType
            self.tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("html")
        }

        deinit {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        func loadHTMLWithFileAccess(_ html: String, baseURL: URL?, into webView: WKWebView) {
            guard let baseURL = baseURL else {
                webView.loadHTMLString(html, baseURL: nil)
                return
            }
            let baseTag = "<base href=\"\(baseURL.absoluteString)\">"
            let finalHTML = html.replacingOccurrences(of: "<head>", with: "<head>\n    \(baseTag)")
            do {
                try finalHTML.write(to: tempFileURL, atomically: true, encoding: .utf8)
                webView.loadFileURL(tempFileURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            } catch {
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            if pendingText != nil {
                scheduleRender()
            }
        }

        func scheduleRender() {
            renderWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeRender()
            }
            renderWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }

        private func executeRender() {
            guard let webView = webView, let text = pendingText, pageLoaded else { return }
            pendingText = nil

            let escaped = MarkdownPreviewView.escapeForJS(text)
            let jsCall: String
            switch previewType {
            case .markdown:
                jsCall = "renderMarkdown(`\(escaped)`)"
            case .html:
                jsCall = "updateContent(`\(escaped)`)"
            case .image:
                return
            }
            webView.evaluateJavaScript(jsCall) { _, error in
                if let error = error {
                    print("[Stuped] Render error: \(error.localizedDescription)")
                }
            }
        }
    }
}
