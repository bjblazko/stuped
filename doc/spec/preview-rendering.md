# Specification: Preview Rendering

## Files

- `Stuped/Views/Preview/MarkdownPreviewView.swift`
- `Stuped/Views/Preview/PreviewFileAccess.swift`
- `Stuped/Views/Preview/ImagePreviewView.swift`

## Overview

Preview rendering handles three content types: Markdown, HTML, and images.

`MarkdownPreviewView` is an `NSViewRepresentable` wrapping `WKWebView`. It renders Markdown or HTML content with live updates as the user types.

In folder mode, each open previewable tab owns its own `MarkdownPreviewView` inside a retained `DocumentPaneView`, so switching tabs normally returns to the same mounted web view instead of rebuilding a shared preview pane.

`PreviewFileAccess.swift` contains the helper types that keep preview staging out of the user's project tree:

- `PreviewTempStore` writes the generated preview HTML into an app-specific directory under `FileManager.default.temporaryDirectory`.
- `PreviewURLSchemeHandler` serves that staged HTML plus relative local assets through a custom `stuped-preview://` URL space.

`ImagePreviewView` is a SwiftUI view that displays image files using `NSImage`, with dimensions and file size info.

## MarkdownPreviewView Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `text` | `String` | Content to render |
| `previewType` | `PreviewType` | `.markdown` or `.html` |
| `fileURL` | `URL?` | Source file URL, used to derive `baseURL` for resolving relative local assets |
| `scrollPosition` | `CGPoint` | Preview viewport origin owned by the surrounding `DocumentPaneView` |
| `onScrollPositionChanged` | `(CGPoint) -> Void` | Callback used to keep the pane-local preview viewport in sync |

## Rendering Paths

### Markdown (`.markdown`)

The initial HTML page is built by `buildMarkdownHTML(_:)` which embeds all JavaScript and CSS resources into a single self-contained HTML document:

**Inlined resources:**

| Resource | Purpose |
|----------|---------|
| `markdown-it.min.js` | Markdown-to-HTML parser |
| `highlight.min.js` | Syntax highlighting for fenced code blocks |
| `mermaid.min.js` | Diagram rendering for `mermaid` code blocks (embedded as a `data:` script URL so preview still works under restricted file access) |
| `preview-styles.css` | GitHub-style typography and layout |
| `hljs-github.css` | Light mode code theme |
| `hljs-github-dark.css` | Dark mode code theme (via `prefers-color-scheme: dark` media query) |

**markdown-it configuration:**

| Option | Value |
|--------|-------|
| `html` | `true` (allow raw HTML in Markdown) |
| `linkify` | `true` (auto-link URLs) |
| `typographer` | `true` (smart quotes, dashes) |
| `highlight` | Custom function integrating highlight.js and Mermaid |

**Mermaid handling:**

- Code blocks with language `mermaid` are rendered as `<pre class="mermaid">` elements.
- After markdown-it renders, all `.mermaid` elements are processed by `mermaid.render()`.
- Mermaid theme follows system appearance (`dark` or `default`).
- An appearance change listener re-initializes Mermaid and re-renders.

**JavaScript API:**

- `renderMarkdown(text)` -- parses Markdown, renders to `#content` div, processes Mermaid blocks, preserves scroll position.
- `window._lastMarkdown` -- stores last rendered text for re-render on theme change.

### HTML (`.html`)

The initial HTML page is built by `buildRawHTML(_:)`:

- Minimal wrapper: `<!DOCTYPE html>`, `<meta charset="utf-8">`, `<div id="content">`.
- Content is loaded directly (no Markdown processing, no highlight.js, no Mermaid).
- `updateContent(newHTML)` JavaScript function replaces `#content` innerHTML.

## Live Update Mechanism

### Debouncing

Updates are debounced at **300ms** via `DispatchWorkItem` on the main queue.

### Update Flow

1. SwiftUI calls `updateNSView` when `text` changes.
2. Coordinator stores `pendingText` and calls `scheduleRender()`.
3. After 300ms, `executeRender()` runs:
   - Escapes text for JavaScript template literal.
   - Calls `renderMarkdown(...)` for Markdown or `updateContent(...)` for HTML via `WKWebView.evaluateJavaScript`.
4. The `pageLoaded` flag ensures JavaScript is not called before the initial page finishes loading.
5. Scroll-only SwiftUI updates do not trigger a preview re-render; the coordinator only schedules JavaScript updates when `text` actually changed.

If the active file changes to a different parent directory or to a different preview type (`.markdown` vs `.html`), the coordinator performs a full page reload so the new base path and JavaScript wrapper are both refreshed.

### JavaScript Escaping

`escapeForJS(_:)` escapes these characters for safe embedding in a JS template literal:

| Character | Replacement |
|-----------|-------------|
| `\` | `\\` |
| `` ` `` | `` \` `` |
| `$` | `\$` |
| `\n` | `\\n` |
| `\r` | `\\r` |

## Resource Loading

`loadResource(_:ext:)` loads files from the app bundle:

1. First tries `Bundle.main.url(forResource:withExtension:subdirectory:"Resources")`.
2. Falls back to `Bundle.main.url(forResource:withExtension:)`.
3. Returns empty string if not found.

`dataURL(for:mimeType:)` base64-encodes bundled text resources that need to be referenced as script URLs without relying on bundle `file://` access from the web content process.

## Local Asset Resolution and Temp Storage

The `fileURL` parameter is used to derive a `baseURL` (the file's parent directory). Relative local assets are resolved without writing helper files into that directory:

1. The generated preview document is written to an app-specific temp directory under `FileManager.default.temporaryDirectory`.
2. The `WKWebView` loads `stuped-preview://preview/index.html` using a per-view `WKURLSchemeHandler`.
3. A `<base href="stuped-preview://preview/root/">` tag is injected into the HTML `<head>` when `baseURL` exists, so relative URLs inside Markdown or raw HTML resolve through the custom scheme.
4. The scheme handler maps `/root/...` requests back to files under `baseURL`, but only if the resolved real path stays inside that directory after standardisation and symlink resolution.

This keeps preview temp files in a location that is private to the current macOS user and automatically cleaned up by the OS, while preserving least-privilege access to relative assets in the active file's directory.

If staging the preview HTML fails, the view logs the error and falls back to `loadHTMLString`. In that fallback path, relative local assets may not render because there is no custom-scheme-backed file access.

The coordinator still cleans up its own temp directory during normal teardown, and pending text updates are flushed after a reload once `webView(_:didFinish:)` fires.

## Preview Viewport Retention

The HTML wrappers install a small JavaScript bridge that reports `window.scrollX` / `window.scrollY` back to Swift via a `WKScriptMessageHandler`.

- User scrolling is throttled with `requestAnimationFrame`.
- The coordinator writes the latest preview position back to the owning `DocumentPaneView` through `onScrollPositionChanged`.
- After a full page load, the coordinator restores the saved preview scroll position with `window.scrollTo(...)`, then reports the effective position back to Swift.
- Tab switching normally returns to the same mounted `WKWebView`; the scroll bridge remains important when the preview subtree is remounted inside the same pane, such as switching between Preview and Split.

## Coordinator

| Property | Type | Purpose |
|----------|------|---------|
| `webView` | `WKWebView?` (weak) | Reference to the web view |
| `pendingText` | `String?` | Latest text awaiting render |
| `previewType` | `PreviewType` | Determines which JS function to call |
| `currentBaseURL` | `URL?` | Tracks current baseURL for change detection |
| `pageLoaded` | `Bool` | Set to `true` in `webView(_:didFinish:)` |
| `renderWorkItem` | `DispatchWorkItem?` | Current debounced render task |
| `currentText` | `String` | Last text sent to the web view; avoids re-rendering on scroll-only updates |
| `schemeHandler` | `PreviewURLSchemeHandler` | Serves staged preview HTML and scoped local assets |
| `tempStore` | `PreviewTempStore` | Manages the coordinator's app-temp preview directory |

## ImagePreviewView

### File: `Stuped/Views/Preview/ImagePreviewView.swift`

A SwiftUI view that displays image files natively using `NSImage`.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `fileURL` | `URL` | Path to the image file on disk |

### Behavior

- Loads the image via `NSImage(contentsOf:)` which supports PNG, JPEG, GIF, BMP, TIFF, WebP, HEIC, and ICO formats natively on macOS.
- Displays the image centered and aspect-fit within a scroll view.
- Shows an overlay with image dimensions (pixels) and file size.
- Reloads when `fileURL` changes.
- Shows `ContentUnavailableView` if the image cannot be loaded.
- Image files are shown in preview-only mode (no editor, no view mode picker, no status bar).
