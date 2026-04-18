# ADR-0009: External Script Loading for Large JS Libraries in WKWebView

## Status

Accepted

## Context

The Markdown preview uses WKWebView with several JavaScript libraries loaded as inline `<script>` blocks: markdown-it (~124 KB), highlight.js (~128 KB), and mermaid (~3.2 MB). The HTML is built in Swift by interpolating each library's source into a template string and then loading it into WKWebView via `loadFileURL`.

Mermaid rendering was intermittently broken. Debugging revealed that `typeof mermaid` evaluated to `undefined` inside WKWebView, even though the identical HTML rendered correctly in Safari. The smaller libraries (markdown-it, highlight.js) loaded fine in both environments.

**Root cause:** WKWebView silently fails to execute very large inline `<script>` blocks. Unlike Safari, WKWebView runs web content in a separate process with stricter resource limits. When the inline mermaid script (~3.2 MB) exceeded these limits, WKWebView dropped the script without any error, leaving the `mermaid` global undefined. There is no documented size threshold; the failure is silent and produces no JavaScript errors, console warnings, or delegate callbacks, making it difficult to diagnose.

## Decision

Load large JavaScript libraries via `<script src="file://...">` referencing bundled resource files, instead of inlining their source into the HTML string.

Specifically:

- **markdown-it** and **highlight.js** (~124-128 KB each): remain inline -- well within safe limits and avoids an extra file-access dependency.
- **mermaid** (~3.2 MB): loaded via `<script src="file:///path/to/mermaid.min.js">` using the bundle URL from `Bundle.main.url(forResource:withExtension:subdirectory:)`.

The WKWebView uses `loadFileURL(_:allowingReadAccessTo:)` with access granted to the directory of the file being previewed. This allows the internal script reference to resolve correctly while preventing access to the rest of the filesystem.

## Consequences

- Mermaid diagrams render reliably in WKWebView.
- The generated HTML string is ~3 MB smaller, reducing memory pressure during string interpolation and temp-file writes.
- If a new large JS library is added in the future, it must be loaded via `<script src>`, not inlined. As a rule of thumb: **do not inline scripts larger than ~500 KB into WKWebView HTML**.
- The `loadHTMLString` fallback path (used when `baseURL` is nil) cannot resolve `file://` script URLs. This path is currently unused in practice since documents always have a file URL, but if it ever activates, mermaid will not load. This is an acceptable trade-off.
