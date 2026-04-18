# ADR-0003: WebKit for Preview Rendering

## Status

Accepted

## Context

Stuped needs to render Markdown as formatted HTML with syntax-highlighted code blocks, Mermaid diagrams, and dark/light mode support. HTML files should also be previewable.

Options considered:

1. **Native SwiftUI rendering** (e.g., `AttributedString` with Markdown parsing): limited styling, no Mermaid, no code highlighting.
2. **WKWebView with JavaScript libraries**: full HTML/CSS/JS capabilities.
3. **Third-party Swift Markdown renderers**: varying quality, no Mermaid.

## Decision

Use `WKWebView` with bundled JavaScript libraries:

- **markdown-it** for Markdown-to-HTML conversion (CommonMark + extensions).
- **highlight.js** for syntax highlighting within code blocks.
- **mermaid.js** for diagram rendering.

All JS/CSS is inlined into a single HTML string (no external loading, no network access). Updates are pushed via `WKWebView.evaluateJavaScript()` with debouncing.

To mitigate the security risks of being an unsandboxed app, the `WKWebView` is configured with restricted file access:
- `loadFileURL` is used with `allowingReadAccessTo` limited to the directory of the file being previewed, rather than the filesystem root.
- Mermaid is configured with `securityLevel: 'strict'` to prevent malicious diagram definitions from executing arbitrary scripts.

## Consequences

### Positive

- Rich, battle-tested rendering with GitHub-style output.
- Mermaid diagrams work out of the box.
- Dark/light mode via CSS `prefers-color-scheme` media query.
- No network dependency (all resources bundled).

### Negative

- ~3.3 MB of bundled JS (mostly mermaid.min.js).
- WKWebView has process overhead (each instance runs in a separate process).
- JavaScript escaping is required for content injection, with potential edge cases.
- Initial page load latency (~300ms) before the first render can execute.
