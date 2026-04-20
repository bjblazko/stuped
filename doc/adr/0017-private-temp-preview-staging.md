# ADR-0017: Private Temp Preview Staging via Custom URL Scheme

## Status

Accepted

## Context

Markdown and HTML preview need a real document URL so relative local assets such as `![](./images/example.png)` continue to resolve inside `WKWebView`.

The previous implementation achieved this by writing a hidden `.stuped-preview-<uuid>.html` file directly into the active file's parent directory and loading it with `loadFileURL(_:allowingReadAccessTo:)`.

That caused two problems:

1. Preview left helper files inside user project folders.
2. Cleanup depended on the preview coordinator shutting down cleanly; crashes or forced quits could leave stale hidden files behind.

The replacement must keep preview staging in a per-user OS-managed temp location while preserving least-privilege access to relative assets under the active file's parent directory.

## Decision

Use an app-specific temp store under `FileManager.default.temporaryDirectory` together with a per-webview custom `WKURLSchemeHandler`.

Specifically:

- `PreviewTempStore` writes the generated preview HTML to `.../com.huepattl.Stuped.preview/<uuid>/index.html` in the current user's temporary directory.
- `WKWebView` loads `stuped-preview://preview/index.html` instead of a `file://` URL in the project tree.
- The generated preview document injects `<base href="stuped-preview://preview/root/">` whenever the active file has a parent directory.
- `PreviewURLSchemeHandler` serves:
  - `/index.html` from the staged temp file
  - `/root/...` from the active file's parent directory, but only if the resolved real path remains inside that directory after standardisation and symlink resolution
- If temp staging fails, the preview falls back to `loadHTMLString`, accepting that relative local assets may not render in that degraded path.

Legacy `.stuped-preview-*.html` files already present in user project folders are not deleted automatically by this change.

## Consequences

### Positive

- No new preview helper files are written into the opened folder tree.
- Preview temp files are stored in a user-private macOS temp location and are eligible for OS cleanup.
- Relative local assets continue to work for Markdown and raw HTML preview.
- Access remains scoped to the active file's parent directory rather than a broad filesystem ancestor.

### Negative

- Preview loading now depends on a custom scheme handler in addition to `WKWebView` itself.
- Relative assets that rely on escaping above the active file's parent directory remain blocked.
- The fallback `loadHTMLString` path still cannot provide scoped local file access if temp staging fails.
