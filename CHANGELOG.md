# 1Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
