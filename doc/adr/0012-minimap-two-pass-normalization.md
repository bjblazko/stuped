# ADR 0012 — Mini-Map Two-Pass Width Normalisation

**Status:** Accepted

## Context

The mini-map renders each logical line as a scaled horizontal bar. The bar width must express how long the line is relative to the document's longest line. The naïve approach used `textContainer.containerSize.width` as the normalisation denominator:

```swift
let containerWidth = max(textContainer.containerSize.width, 1)
let lineWidth = usedRect.width / containerWidth
```

This broke when word wrap is **off**: `applyWordWrap` sets `containerSize.width = CGFloat.greatestFiniteMagnitude`, making every `lineWidth ≈ 0` and collapsing all bars to the minimum 2 pt.

A second issue: the mini-map showed no indicator for the current text selection. When a user selected a block, the editor displayed a coloured highlight but the mini-map showed nothing — the only overlay was the viewport rectangle, which covers a different region and uses a different colour.

## Decision

### Width normalisation — two-pass enumeration

Replace the single pass with two passes over `layoutManager.enumerateLineFragments`:

**Pass 1** finds `maxLineWidth = max(usedRect.width)` across all logical-line-start fragments. `usedRect` is in layout coordinates and is always finite regardless of `containerSize`.

**Pass 2** draws bars using `containerWidth = maxLineWidth` as the denominator. This scales every bar relative to the longest visible line in the document, which is the correct semantic in both word-wrap modes.

### Selection overlay — third enumeration pass

After the bar pass, a third pass reads `textView.selectedRanges` and tints every mini-map line slot that intersects the selection using `NSColor.selectedTextBackgroundColor` at 45 % / 35 % alpha (dark / light). The draw order is:

```
background → bars → selection overlay → viewport rect
```

This gives the selection indicator higher visual priority than the bars but lower than the viewport rect.

`textViewDidChangeSelection` in `CodeEditorView.Coordinator` triggers `miniMapView.needsDisplay = true` so the overlay updates on every selection change without waiting for a text edit.

## Consequences

- Three passes through `enumerateLineFragments` per draw call. NSLayoutManager caches layout, so each enumeration is a fast traversal of an already-computed structure. Bounded by the 5000-line cap already in place.
- Bar widths now scale relative to the longest line, not the container width. In word-wrap-on mode this is visually equivalent to before (longest line fills the container); in word-wrap-off mode bars now reflect actual line lengths.
- Selection is visible in the mini-map and updates immediately, matching the behaviour of mainstream code editors (VS Code, JetBrains).
