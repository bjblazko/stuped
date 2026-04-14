# Specification: Path Bar

## File: `Stuped/Views/PathBarView.swift`

## Overview

A horizontal bar above the editor showing the full file path as clickable breadcrumb components, plus the git branch name.

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `fileURL` | `URL?` | Path to display |
| `gitInfo` | `GitInfo?` | Git branch and remote info |
| `onNavigate` | `((URL) -> Void)?` | Callback when a path component is clicked |

## Layout

```
+----------------------------------------------------------------------+
| [folder] Users > [folder] name > [folder] project > [doc] file.swift | [branch] main |
+----------------------------------------------------------------------+
```

### Left section: path components

- `url.pathComponents` is filtered to remove the root `"/"` element.
- Each component is a `Button` with `.buttonStyle(.plain)`.
- Components are separated by chevron-right icons (`chevron.right`, 8pt semibold, quaternary color).
- Each component shows an icon + name:
  - Directories: `folder` icon, `.secondary` color.
  - Last component (file): type-specific icon, `.primary` color.
- Font: system 11pt.
- Wrapped in a horizontal `ScrollView` (no scroll indicators).
- Auto-scrolls to the last component (`ScrollViewReader` with id `"last"`).
- Hover cursor: `NSCursor.pointingHand`.

### Right section: git branch

- Only shown when `gitInfo?.branchName` is non-nil.
- Separated by a `Divider` (12pt height).
- Icon: `arrow.triangle.branch` (10pt, secondary).
- Text: branch name (11pt, secondary, single line).
- Tooltip (`.help`): `gitInfo?.remoteURL ?? "No remote configured"`.

## Styling

| Property | Value |
|----------|-------|
| Vertical padding | 4pt |
| Horizontal padding (path) | 12pt |
| Background | `.bar` |
| Bottom edge | `Divider()` overlay |

## File Icon Logic

| Extension | Icon |
|-----------|------|
| Markdown extensions | `doc.richtext` |
| `html`, `htm`, `xhtml` | `globe` |
| Image extensions | `photo` |
| Everything else | `doc` |

## Context Menu

Each breadcrumb component has a right-click context menu with a **Copy Path** action. This copies the absolute path from root up to and including the clicked component to the system clipboard via `NSPasteboard.general`.

The path is built by `buildPath(componentIndex:fullURL:)`, which is also used by the navigation callback.

## Navigation Callback

When a component is clicked:

1. The component index (0-based, relative to the filtered array) is mapped to the full `pathComponents` array (offset by 1 to skip `"/"`).
2. A path string is reconstructed from root to the clicked component.
3. `onNavigate?(URL(fileURLWithPath: path))` is called.

In `ContentView`, the callback calls `navigateToPath(_:)`:

- **Directory**: loads it in the sidebar tree, clears file selection, shows sidebar.
- **File**: loads the parent directory in the tree, selects the file, shows sidebar.
