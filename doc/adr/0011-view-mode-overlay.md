# ADR 0011: View Mode Switcher as In-Editor Overlay

**Status:** Accepted  
**Date:** 2026-04-14

## Context

The Edit / Preview / Split mode picker was a segmented control in the window toolbar. This had two problems:

1. **Visibility** — the control appeared in the toolbar regardless of file type, even though it is only meaningful for Markdown and HTML files. It occupied permanent toolbar space and looked out of place for plain source files.
2. **Discoverability vs. clutter trade-off** — hiding it via `if isPreviewable` made it appear and disappear from the toolbar, shifting the positions of other toolbar items.

## Decision

Remove the toolbar segmented control entirely. Replace it with a small frosted-glass overlay anchored to the top-trailing corner of the editor area, rendered only when `isPreviewable && !isImageFile`:

```swift
editorArea
    .overlay(alignment: .topTrailing) {
        if isPreviewable && !isImageFile {
            viewModeOverlay  // three icon buttons in .ultraThinMaterial pill
        }
    }
```

Each button is a plain `Button` with an SF Symbol icon (`doc.plaintext`, `rectangle.split.2x1`, `eye`), a `.help(tooltip)`, and a highlighted background for the active mode. The overlay uses `.ultraThinMaterial` so it adapts to both light and dark mode and does not obscure much of the editor.

## Alternatives Considered

**Keep the toolbar control** — simple, but pollutes the toolbar for non-previewable files and shifts other items when it appears/disappears.

**Right-click context menu** — discoverable only if users know to right-click; not suitable as the primary mechanism.

**Keyboard shortcuts only** — efficient for power users, but not discoverable without a visual affordance.

## Consequences

- The toolbar is simpler and consistent regardless of file type.
- For Markdown/HTML files, the overlay floats over the top-right of the editor. It does not interfere with the split-view divider or the status bar.
- In split mode the overlay appears over the editor pane (left side of the `HSplitView`), which is correct since the mode control applies to the whole view.
