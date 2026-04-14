# Specification: Preview Rendering

## Files

- `Stuped/Views/Preview/MarkdownPreviewView.swift`
- `Stuped/Views/Preview/ImagePreviewView.swift`

## Overview

Preview rendering handles three content types: Markdown, HTML, and images.

`MarkdownPreviewView` is an `NSViewRepresentable` wrapping `WKWebView`. It renders Markdown or HTML content with live updates as the user types.

`ImagePreviewView` is a SwiftUI view that displays image files using `NSImage`, with dimensions and file size info.

## MarkdownPreviewView Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `text` | `String` | Content to render |
| `previewType` | `PreviewType` | `.markdown` or `.html` |
| `fileURL` | `URL?` | Source file URL, used to derive `baseURL` for resolving relative image paths |

## Rendering Paths

### Markdown (`.markdown`)

The initial HTML page is built by `buildMarkdownHTML(_:)` which inlines all JavaScript and CSS resources into a single self-contained HTML document:

**Inlined resources:**

| Resource | Purpose |
|----------|---------|
| `markdown-it.min.js` | Markdown-to-HTML parser |
| `highlight.min.js` | Syntax highlighting for fenced code blocks |
| `mermaid.min.js` | Diagram rendering for `mermaid` code blocks |
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

## Base URL for Local Images

The `fileURL` parameter is used to derive a `baseURL` (the file's parent directory). To grant the WKWebView web content process read access to local image files, the generated HTML is written to a temporary file and loaded via `loadFileURL(_:allowingReadAccessTo:)` instead of `loadHTMLString`. A `<base href="...">` tag pointing to the markdown file's parent directory is injected into the HTML `<head>` so that relative image paths (e.g. `![](./images/photo.png)`) resolve correctly against the file's location — not the temp file's location.

Each Coordinator owns a unique temp file (UUID-based name in `NSTemporaryDirectory`) that is cleaned up on deallocation. When `baseURL` is nil (unsaved documents), the view falls back to `loadHTMLString` without file access.

When the user switches to a file in a different directory, the coordinator detects the `baseURL` change and performs a full page reload (rather than just a JavaScript update) to establish the new base and file-access grant.

After a page reload, the coordinator flushes any pending text update once `webView(_:didFinish:)` fires.

## Coordinator

| Property | Type | Purpose |
|----------|------|---------|
| `webView` | `WKWebView?` (weak) | Reference to the web view |
| `pendingText` | `String?` | Latest text awaiting render |
| `previewType` | `PreviewType` | Determines which JS function to call |
| `currentBaseURL` | `URL?` | Tracks current baseURL for change detection |
| `pageLoaded` | `Bool` | Set to `true` in `webView(_:didFinish:)` |
| `renderWorkItem` | `DispatchWorkItem?` | Current debounced render task |
| `tempFileURL` | `URL` | Unique temp file for `loadFileURL`-based loading |

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
