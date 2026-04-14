# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Custom About dialog with copyright, links to Hüpattl! Software website, GitHub project, and Apache License 2.0

### Changed

- Folder browser window title now shows the name of the open folder instead of the static "Stuped — Folder"

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
