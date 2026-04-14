# ADR 0010: In-Window Tab Management for Folder Mode

**Status:** Accepted  
**Date:** 2026-04-14

## Context

In folder mode the user browses a directory tree and opens files by clicking them in the sidebar. The original implementation replaced the editor content on every click — there was no way to keep multiple files open simultaneously. Users familiar with editors like VS Code, Xcode, or Zed expect to switch between open files without losing unsaved edits.

## Decision

Introduce a lightweight tab layer owned by `FolderBrowserView`, sitting between the scene and `ContentView`:

- **`TabItem`** (`@Observable` class) — holds `fileURL`, `text` (live editor content), `savedText` (last-saved snapshot), and a computed `isDirty`.
- **`TabManager`** (`@Observable` class) — owns `[TabItem]` and `activeTabID`; exposes `open(url:)` (load or switch) and `close(id:)`.
- **`FolderBrowserView`** — owns `TabManager`; provides `activeDocumentBinding` (a `Binding<StupedDocument>` whose get/set route through the active tab's text) to `ContentView`.
- **`TabBarView`** — a horizontal `ScrollView` of tab cells rendered in `ContentView`'s detail pane, above `PathBarView`.

### Sidebar-click flow

Sidebar selection changes trigger `ContentView`'s `onFileSelected` callback → `TabManager.open(url:)` → creates a new `TabItem` (loading from disk) or activates an existing one.

### Tab-click flow

`TabBarView` calls `TabManager.open(url:)` for the selected tab. If already active, nothing happens. If switching, `TabManager` posts `.stupedTabSwitched` with the target URL. `ContentView` receives the notification and updates `sidebarFileURL` (sidebar highlight) and `viewMode` without reading the file from disk — the content is already in `TabItem.text` and reaches the editor via the binding.

### Dirty tracking

`TabItem.isDirty` is computed as `text != savedText`. Text changes flow through `activeDocumentBinding.set`, keeping `TabItem.text` current. After a successful save, `TabItem.markSaved()` sets `savedText = text`, clearing the dirty state. The tab bar renders an accent-color dot on dirty tabs.

## Alternatives Considered

**Single document with re-load on switch** — simple, but loses unsaved edits when switching tabs, which is a significant UX regression.

**SwiftUI `TabView`** — not suited for a code-editor tab bar style; the platform style is macOS window tabs (separate windows), not in-pane document tabs.

**macOS native window tabbing (`NSWindow.tabbingMode`)** — merges separate windows into a tab bar, but each tab is a full window with its own process/state. Doesn't allow switching between files within a single folder-mode window without full re-loads.

## Consequences

- Each open file's text is kept in memory. For large repos with many open tabs, memory usage grows linearly.
- Cursor position and scroll offset are not yet preserved per tab (reset on switch). This is a known limitation for a future iteration.
- `ContentView` gained three optional parameters (`tabManager`, `onFileSelected`, `onFileSaved`) and one new `onReceive` handler. The single-file mode code path is unchanged.
