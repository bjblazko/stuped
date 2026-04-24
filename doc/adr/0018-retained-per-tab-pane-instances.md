# ADR-0018: Retained Per-Tab Pane Instances

## Status

Accepted

## Context

Folder-mode tabs originally shared one `ContentView` detail pane. Switching tabs reused that pane with a different `TabItem`, so the visible `NSTextView` and `WKWebView` were often rebuilt or rebound for a different document.

That forced the app to serialize UI details such as editor scroll position, preview scroll position, and view mode into `TabItem` just to make tab switches feel stable. It also made the architecture diverge from the expected desktop-editor model where each open tab owns its own live editor context until the tab is closed.

## Decision

Retain one mounted `DocumentPaneView` per open tab and switch visibility instead of reconstructing one shared detail pane.

Specifically:

- `ContentView` renders the folder-mode detail area as a `ZStack` of `DocumentPaneView` instances, one for each open `TabItem`.
- Only the active pane is visible and hit-testable, but inactive panes remain mounted while their tabs stay open.
- `DocumentPaneView` owns pane-local editor state, git info, and viewport state.
- `TabItem` continues to own document state (`fileURL`, `text`, `savedText`, `viewMode`) but no longer stores editor or preview scroll positions.
- Single-file mode reuses the same `DocumentPaneView` building block, but with only one pane and no tab strip.

## Consequences

### Positive

- Returning to a tab shows the same live editor and preview instances instead of restoring a reconstructed pane.
- View mode and viewport retention on tab switch become a natural consequence of the mounted pane model.
- The shared implementation between folder mode and single-file mode increases consistency.
- The tab model becomes simpler because viewport state no longer has to be serialized into `TabItem`.

### Negative

- Memory usage grows with the number of open tabs because inactive panes remain mounted.
- Hidden `WKWebView` and `NSTextView` instances still exist, but heavyweight inactive work is now suspended where practical (preview JS renders, syntax highlighting, mini-map/gutter redraws, scroll restore, path-bar/status-bar chrome, and per-pane git metadata refresh).
- View-mode changes inside a pane can still remount the editor or preview subtree, so pane-local viewport retention remains useful there.
