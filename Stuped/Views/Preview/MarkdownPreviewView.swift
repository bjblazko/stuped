import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let text: String
    let previewType: PreviewType
    var fileURL: URL?
    var isActive: Bool = true
    var scrollPosition: CGPoint = .zero
    var onScrollPositionChanged: ((CGPoint) -> Void)? = nil

    private static let scrollMessageHandlerName = "stupedPreviewScroll"

    private var baseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: PreviewURLSchemeHandler.scheme)
        configuration.userContentController.add(context.coordinator, name: Self.scrollMessageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.currentBaseURL = baseURL
        context.coordinator.currentText = text

        let html = Self.buildHTML(text: text, previewType: previewType)
        context.coordinator.loadPreviewHTML(html, baseURL: baseURL, into: webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let wasActive = context.coordinator.currentIsActive
        context.coordinator.currentIsActive = isActive
        if context.coordinator.previewType != previewType || context.coordinator.currentBaseURL != baseURL {
            // File moved to a different directory or preview type — full page reload needed.
            context.coordinator.previewType = previewType
            context.coordinator.currentBaseURL = baseURL
            context.coordinator.currentText = text
            context.coordinator.pageLoaded = false
            let html = Self.buildHTML(text: text, previewType: previewType)
            context.coordinator.loadPreviewHTML(html, baseURL: baseURL, into: webView)
            return
        }
        context.coordinator.previewType = previewType
        if context.coordinator.currentText != text {
            context.coordinator.currentText = text
            context.coordinator.pendingText = text
            if isActive {
                context.coordinator.scheduleRender()
            }
        }
        if isActive {
            if !wasActive, context.coordinator.pendingText != nil {
                context.coordinator.scheduleRender()
            } else {
                context.coordinator.restoreScrollPositionIfNeeded()
            }
        }
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
        let encoded = base64EncodedUTF8(markdown)

        let mdItJS = loadResource("markdown-it.min", ext: "js")
        let hljsJS = loadResource("highlight.min", ext: "js")
        let mermaidJS = loadResource("mermaid.min", ext: "js")
        let mermaidDataURL = dataURL(for: mermaidJS, mimeType: "text/javascript")
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
            <script src="\(mermaidDataURL)"></script>
            <script>
                \(scrollBridgeScript())
                \(base64DecodeScript())
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

                function configureMermaid(isDark) {
                    if (!window.mermaid) { return; }
                    mermaid.initialize({
                        startOnLoad: false,
                        theme: isDark ? 'dark' : 'default',
                        securityLevel: 'strict'
                    });
                }

                configureMermaid(window.matchMedia('(prefers-color-scheme: dark)').matches);

                window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function(e) {
                    configureMermaid(e.matches);
                    if (window._lastMarkdown) { renderMarkdown(window._lastMarkdown); }
                });

                let mermaidCounter = 0;

                async function renderMarkdown(text) {
                    window._lastMarkdown = text;
                    const scrollX = window.scrollX;
                    const scrollY = window.scrollY;
                    document.getElementById('content').innerHTML = md.render(text);

                    const els = document.querySelectorAll('pre.mermaid');
                    for (const el of els) {
                        if (!window.mermaid) { continue; }
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
                    window.scrollTo(scrollX, scrollY);
                    reportScrollPosition();
                }

                renderMarkdown(decodeBase64UTF8('\(encoded)'));
            </script>
        </body>
        </html>
        """
    }

    private static func buildRawHTML(_ html: String) -> String {
        let encoded = base64EncodedUTF8(html)
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body>
            <div id="content"></div>
            <script>
                \(scrollBridgeScript())
                \(base64DecodeScript())
                function updateContent(newHTML) {
                    const scrollX = window.scrollX;
                    const scrollY = window.scrollY;
                    document.getElementById('content').innerHTML = newHTML;
                    window.scrollTo(scrollX, scrollY);
                    reportScrollPosition();
                }
                updateContent(decodeBase64UTF8('\(encoded)'));
            </script>
        </body>
        </html>
        """
    }

    private static func base64EncodedUTF8(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    private static func dataURL(for text: String, mimeType: String) -> String {
        let encoded = Data(text.utf8).base64EncodedString()
        return "data:\(mimeType);base64,\(encoded)"
    }

    private static func scrollBridgeScript() -> String {
        """
        (function() {
            let scrollReportPending = { value: false };
            window.reportScrollPosition = function() {
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(scrollMessageHandlerName);
                if (!handler) { return; }
                handler.postMessage({ x: window.scrollX, y: window.scrollY });
            };
            window.queueScrollReport = function() {
                if (scrollReportPending.value) { return; }
                scrollReportPending.value = true;
                window.requestAnimationFrame(function() {
                    scrollReportPending.value = false;
                    window.reportScrollPosition();
                });
            };
            window.addEventListener('scroll', window.queueScrollReport, { passive: true });
        })();
        """
    }

    private static func base64DecodeScript() -> String {
        """
        function decodeBase64UTF8(base64) {
            const binary = atob(base64);
            const bytes = Uint8Array.from(binary, function(char) {
                return char.charCodeAt(0);
            });
            return new TextDecoder().decode(bytes);
        }
        """
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

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownPreviewView
        weak var webView: WKWebView?
        var pendingText: String?
        var currentText: String
        var previewType: PreviewType
        var currentBaseURL: URL?
        private var renderWorkItem: DispatchWorkItem?
        var pageLoaded = false
        private var lastRestoredScrollPosition: CGPoint?
        var currentIsActive: Bool

        let schemeHandler = PreviewURLSchemeHandler()
        private let tempStore = PreviewTempStore()

        init(_ parent: MarkdownPreviewView) {
            self.parent = parent
            self.currentText = parent.text
            self.previewType = parent.previewType
            self.currentIsActive = parent.isActive
        }

        deinit {
            renderWorkItem?.cancel()
            schemeHandler.clearSession()
            tempStore.cleanup()
        }

        func loadPreviewHTML(_ html: String, baseURL: URL?, into webView: WKWebView) {
            let finalHTML: String
            if baseURL != nil {
                let baseTag = "<base href=\"\(PreviewURLSchemeHandler.rootURL.absoluteString)\">"
                finalHTML = html.replacingOccurrences(of: "<head>", with: "<head>\n    \(baseTag)")
            } else {
                finalHTML = html
            }

            do {
                let htmlFileURL = try tempStore.write(html: finalHTML)
                schemeHandler.update(htmlFileURL: htmlFileURL, baseURL: baseURL)

                var request = URLRequest(url: PreviewURLSchemeHandler.previewURL)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                webView.load(request)
            } catch {
                print("[Stuped] Failed to stage preview HTML: \(error.localizedDescription)")
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            if currentIsActive {
                restoreScrollPosition()
            }
            if currentIsActive, pendingText != nil {
                scheduleRender()
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == MarkdownPreviewView.scrollMessageHandlerName,
                  let payload = message.body as? [String: Any],
                  let x = payload["x"] as? Double,
                  let y = payload["y"] as? Double else { return }
            let position = CGPoint(x: x, y: y)
            lastRestoredScrollPosition = position
            parent.onScrollPositionChanged?(position)
        }

        func scheduleRender() {
            guard currentIsActive else { return }
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

            let encoded = MarkdownPreviewView.base64EncodedUTF8(text)
            let jsCall: String
            switch previewType {
            case .markdown:
                jsCall = "renderMarkdown(decodeBase64UTF8('\(encoded)'))"
            case .html:
                jsCall = "updateContent(decodeBase64UTF8('\(encoded)'))"
            case .image:
                return
            }
            webView.evaluateJavaScript(jsCall) { _, error in
                if let error = error {
                    print("[Stuped] Render error: \(error.localizedDescription)")
                }
            }
        }

        func restoreScrollPositionIfNeeded() {
            guard currentIsActive else { return }
            guard lastRestoredScrollPosition != parent.scrollPosition else { return }
            restoreScrollPosition()
        }

        private func restoreScrollPosition() {
            guard pageLoaded, let webView else { return }
            let x = parent.scrollPosition.x
            let y = parent.scrollPosition.y
            let jsCall = """
            window.scrollTo(\(x), \(y));
            window.requestAnimationFrame(function() {
                window.scrollTo(\(x), \(y));
                if (window.reportScrollPosition) { window.reportScrollPosition(); }
            });
            """
            webView.evaluateJavaScript(jsCall) { [weak self] _, error in
                if let error = error {
                    print("[Stuped] Preview scroll restore error: \(error.localizedDescription)")
                    return
                }
                self?.lastRestoredScrollPosition = CGPoint(x: x, y: y)
            }
        }
    }
}
