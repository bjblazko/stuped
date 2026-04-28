# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.4] - 2026-04-28

### Fixed

- Eliminated high idle CPU usage by offloading file-tree `FSEventStream` processing to a background utility queue, preventing main-thread saturation.
- Aggressively suspended high-frequency UI tasks (syntax highlighting, mini-map, Markdown preview rendering) when the application is inactive.
- Coalesced Git status refreshes across all open tabs, and tied status refreshes to application lifecycle state to avoid background work while idle.
- Reduced SwiftUI layout thrashing by optimizing `PathBarView` and `FileTreeSidebar` components with `Equatable` conformance and explicit toolbar isolation.

## [0.6.3] - 2026-04-24

### Fixed

- Folder-mode idle CPU is reduced by making file-tree FSEvents handling more selective: only visible structural changes rebuild the sidebar, while git-relevant content and metadata changes trigger lighter-weight status refreshes.
- Repeated folder-mode git status refreshes now reuse the resolved repository root instead of re-running repository discovery for every debounced refresh.
- Inactive retained tabs now pause heavyweight editor and preview work, deferring syntax highlighting, mini-map/gutter redraw cost, and preview JavaScript updates until the tab becomes active again.
- Folder-mode git refreshes now run through a single coalesced queue, preventing overlapping `git status` subprocesses during filesystem event bursts and rate-limiting background refreshes while the project is otherwise idle.
- Inactive retained tabs no longer keep path-bar and status-bar chrome mounted, reducing hidden SwiftUI/AppKit layout work without giving up fast tab restoration.
- File-tree FSEvents bursts now coalesce into one delayed sidebar rebuild instead of repeatedly rebuilding the visible tree on every callback, reducing idle main-thread churn when a noisy project path keeps emitting file events.

## [0.6.2] - 2026-04-23

### Fixed

- Cold-launch fallback window creation now waits briefly for `DocumentGroup` file-open events, so opening a file from Finder or macOS recent documents no longer spawns an extra empty editor window.

## [0.6.1] - 2026-04-23

### Fixed

- Folder mode now avoids repeated recursive file-tree lookups while rendering large expanded sidebars, reducing CPU churn in big folder structures.
- Folder-mode git status refreshes no longer refetch on every file selection change and now debounce filesystem/reactivation bursts to reduce unnecessary background work.
- The **Git Changes** and **Find in Files** panels now enforce usable minimum sizes and reset stale tiny autosaved frames instead of reopening nearly collapsed.

## [0.6.0] - 2026-04-22

### Added

- Folder mode now keeps a **per-session file history** with Finder-style **Back** / **Forward** toolbar buttons. History navigation can switch to an existing tab or reopen a file whose tab was closed later in the session.
- The folder-mode file tree now supports **New File** and **New Folder** actions for the currently selected folder, with inline naming directly in the sidebar. Press **Return** to create the item or **Escape** to cancel the draft row.
- Folder mode now highlights **git working-tree changes** in the file tree: changed files are color-coded and show overlay icons for **new**, **modified**, and **deleted** states where applicable.
- Clicking the folder-mode **git branch badge** now opens a native **Git Changes** window listing changed files grouped by type; selecting an existing file focuses its open tab or opens it in a new one.
- Folder mode now also exposes the **Git Changes** window from **View > Git Changes**.

### Changed

- The folder-browser window title now shows the **active filename** and falls back to the folder name when no file is selected.
- The folder-mode **Cmd+R** quick switcher now prefers the current session's file history, so recently visited files from this run appear first even if their tabs are currently closed.

### Fixed

- `Reveal in File Tree` now scrolls the sidebar so the revealed file stays visible and highlighted even when it lives deep in the project tree.
- The app menu no longer shows **Recent Folders** twice when both the document and folder scenes are active.

## [0.5.4] - 2026-04-21

### Added

- Tabs, file-tree items, and path-bar breadcrumbs now offer `Copy Path` context-menu actions for **name only**, **project-relative path**, and **fully qualified path** clipboard copies.
- Folder browsing now tracks **recent folders** in Stuped itself, exposing them in a dedicated **Recent Folders** menu and in the folder-mode **Cmd+R** quick switcher alongside recent files. macOS-native recent documents continue to power file recents.

## [0.5.3] - 2026-04-21

### Fixed

- Markdown and HTML preview now safely transport document text into the `WKWebView` wrapper so fenced or inline source examples containing literal `</script>` sequences no longer break rendering.

## [0.5.2] - 2026-04-20

### Fixed

- Markdown and HTML preview no longer write hidden `.stuped-preview-*.html` helper files into the opened project folder; preview staging now uses the current user's macOS temporary directory and keeps relative local assets scoped to the active file's parent directory.
- Open tabs now keep their own mounted document panes in memory instead of reconstructing one shared detail pane; switching tabs returns to the same live editor or preview context, including view mode and viewport location.

## [0.5.1] - 2026-04-19

### Changed

- Release CI now builds on GitHub Actions `macos-26` with **Xcode 26.4**, while the app still deploys to **macOS 15+**.

### Fixed

- Clicking a folder in the sidebar now expands/collapses it instead of opening a bogus editor tab for the directory.
- Markdown and split preview render again after switching to files in subfolders; bundled Mermaid loading no longer depends on blocked file-URL access.

## [0.5.0] - 2026-04-19

### Added

- **Green zoom button enters fullscreen** in both file and folder windows via the native SwiftUI `.windowFullScreenBehavior(.enabled)` API.
- **Appearance override** (View menu and View Options toolbar menu): choose *System*, *Light*, or *Dark* to override the macOS appearance per-app. Persists across launches.
- **Reveal in File Tree** (⌘⇧J): expands the sidebar to the active file's location. Also available via tab right-click context menu.
- **View Options toolbar menu** (`slider.horizontal.3` icon): consolidates Word Wrap, Mini-Map, Show Dot Files, Reveal in File Tree, Recent Files, and Search Files into one dropdown. Active toggles show a checkmark.
- **View mode keyboard shortcuts** Cmd+1/2/3 (Edit/Split/Preview) in View menu and toolbar; active only for previewable file types.
- **Tab context menu**: right-clicking any tab shows "Close Tab" and "Close Others".
- Global search (⌘⇧F): **extension filter** (`ext:`) inline in the search bar — type e.g. `swift` to narrow results; clear to search all types.

### Changed

- Dark mode editor and gutter background are now pure black; light mode follows the active syntax-highlight theme.
- File tree uses **lazy loading** — only expanded directories are scanned, improving startup time and memory for large projects.
- FSEvents watcher triggers rebuilds only for changes inside currently expanded paths.
- View-mode switcher moved from a floating overlay to a **dedicated bar** between path bar and editor.
- Global search dialog is now a native **resizable NSPanel** with title bar, close button, drag-to-resize, and position/size memory.
- Global search: results and preview separated by a **draggable VSplitView**.
- Global search: scope always reflects the **currently visible sidebar root**, not the stale project root.
- Global search: default scope changed to **Both** (filename + contents); mode selector is now a native popup button.
- Global search panel closes automatically when a different project folder is opened.

### Fixed

- Markdown preview WKWebView file access restricted to the file's own parent directory (was granting root-level access).
- Mermaid diagram rendering now uses `securityLevel: 'strict'`.
- File tree detects new and deleted files **anywhere** in the project tree via recursive `FSEventStream`; previously only root-level changes were caught.
- Global search: consistent default size (720 × 640 pt) on every launch including the first.
- Global search: search field reliably receives focus on open.
- Global search: stale results from a previous project no longer appear after switching folders.
- Global search: first result immediately visible and highlighted on arrival.
- Global search: line numbers in preview use higher-contrast styling in dark mode.
- CI build uses Xcode 16.2, ensuring modern sidebar and toolbar styling on current macOS.

## [0.4.0] - 2026-04-15

### Fixed

- Open tabs now reflect external file changes immediately: when another process writes to a file that is open (and unmodified) in a tab, the editor reloads from disk automatically. Tabs with unsaved edits are left untouched.

### Added

- Global file search dialog (⌘⇧F): search all files in the open folder tree (including subdirectories) by file name, file contents, or both. Results show file name, relative path, and (for content matches) a preview of the matching line with its line number. Navigate with ↑/↓, open with Enter, dismiss with Escape or click outside.

## [0.3.0] - 2026-04-15

### Added

- Show Dot Files toggle (⌘⇧H) in the View menu reveals hidden files and directories (dotfiles such as `.env`, `.gitignore`, `.claude/`) in the file tree; state persists across sessions
- Cmd+R in folder mode opens a floating "Recent Files" popup (command-palette style) showing open tabs sorted by recency and recently opened files from macOS history; type to filter, ↑/↓ to navigate, Enter or click to switch, Escape to dismiss. Pressing Cmd+R again while the popup is open cycles the selection down one row.
- Mini-map panel on the right side of each editor showing a scaled-down overview of the document; click or drag to scroll. Toggle with View > Toggle Mini-Map (⌘⇧M).

### Fixed

- View mode no longer stays as Split/Preview when opening a non-previewable file in a new tab; it resets to Edit automatically
- Mini-map bar widths were all collapsed to minimum when word wrap is off (caused by dividing by `CGFloat.greatestFiniteMagnitude`); bars now scale relative to the longest line in the document
- Mini-map now shows a selection overlay (using the system selection colour) over lines covered by the current text selection, and redraws whenever the selection changes

## [0.2.0] - 2026-04-14

### Added

- In-window tabs for folder browser mode: opening a file from the sidebar creates a tab; switching tabs preserves unsaved edits; dirty tabs show a blue accent dot; tabs close with ×
- Floating view-mode switcher (Edit / Split / Preview) as a frosted-glass icon overlay in the top-right corner of the editor — only visible for Markdown and HTML files
- File-type icon colors in the sidebar: each language/format group gets a distinct rainbow-spectrum color (Swift → red, JS/TS/JSON → yellow, Go/shell → green, CSS → teal, config → cyan, C/C++ → blue, Ruby/Lua/Elixir → purple, images → pink, …)
- Custom About dialog with app version, copyright "© 2026 Timo Böwing", and links to Hüpattl! Software, GitHub project, and Apache License 2.0

### Changed

- Folder browser window title now shows the parent folder of the selected file (or the root folder name when nothing is selected)
- View-mode segmented control removed from the toolbar (replaced by the in-editor overlay)

## [0.1.0] - 2026-04-14

First release of **Stuped** by Hüpattl! Software.

### Added

- Single-file editing via DocumentGroup (Finder double-click, File > Open)
- Folder browsing mode with hierarchical file tree sidebar (Cmd+Shift+O)
- Syntax highlighting for 100+ languages using HighlighterSwift
- Line number gutter with scroll-aware drawing
- Markdown preview with GitHub-flavored styling via markdown-it
- HTML live preview via WKWebView
- Mermaid diagram rendering in Markdown code blocks
- SVG and raster image preview (PNG, JPEG, GIF, BMP, TIFF, WebP, HEIC, ICO) with dimensions and file size overlay
- Split view mode (editor + preview side by side)
- Edit/Preview/Split segmented control for previewable file types
- Dark and light mode support with automatic theme switching
- Path bar with clickable breadcrumb components and copy-to-clipboard via right-click
- Git branch display in path bar with remote origin URL tooltip
- Status bar showing cursor position, line count, language, indentation, line endings, and encoding
- Real-time file tree watching via kqueue (DispatchSource)
- Binary file detection (null-byte scan in first 8 KB)
- Tab/Shift+Tab indent handling (4-space soft tabs)
- Find bar (Cmd+F) with incremental search
- Find menu (Edit > Find) with Find Next/Previous, Find and Replace, and Use Selection for Find
- Word wrap toggle button in toolbar
- Keyboard shortcut hints in toolbar button tooltips
- Toolbar buttons for Save, Open File, and Open Folder
- Automatic line ending detection (LF, CRLF, CR)
- Automatic indentation detection (tabs, 2-space, 4-space)
- Preview-type gating: picker only shown for Markdown and HTML files
- Cmd+S save shortcut in folder mode

### Fixed

- Mermaid diagrams not rendering in preview (WKWebView silently drops large inline scripts; now loaded via external file URL)
- Markdown preview now renders images with relative paths (use `loadFileURL` with file-system access grant instead of `loadHTMLString`)
- Opening a file from Finder no longer shows a blank "Untitled" window instead of the file content
