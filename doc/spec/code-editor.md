# Specification: Code Editor

## Files

- `Stuped/Views/Editor/CodeEditorView.swift`
- `Stuped/Views/Editor/LineNumberGutterView.swift`
- `Stuped/Views/Editor/MiniMapView.swift`

## Overview

The code editor wraps AppKit's `NSTextView` via `NSViewRepresentable`, adding syntax highlighting, line numbers, and custom key handling.

## NSTextView Configuration

| Setting | Value |
|---------|-------|
| Editable | Yes |
| Selectable | Yes |
| Undo manager | Enabled |
| Auto-quote substitution | Disabled |
| Auto-dash substitution | Disabled |
| Spell checking | Disabled |
| Auto-completion | Disabled |
| Uses find bar | Yes (incremental search) |
| Font | System monospaced, 13pt |
| Text color | `.textColor` (dynamic) |
| Background | `.textBackgroundColor` (dynamic) |
| Insertion point color | `.textColor` (dynamic) |
| Text container inset | 4pt horizontal, 8pt vertical |
| Line spacing | 2pt (via `NSMutableParagraphStyle`) |

## View Hierarchy

```
NSView (container, autoresizing mask)
  +-- LineNumberGutterView (44pt width, pinned left)
  +-- NSScrollView (fills between gutter and mini-map)
  |     +-- NSTextView
  +-- MiniMapView (80pt width, pinned right; hidden when mini-map is off)
```

## Key Handling

### Tab

Inserts 4 space characters at the cursor position (soft tabs).

### Shift+Tab

Removes up to 4 leading spaces from the current line.

## Syntax Highlighting

### Engine

Uses the `Highlighter` class from the HighlighterSwift package, which wraps highlight.js via JavaScriptCore.

### Theme Selection

- Dark mode (`NSAppearance.Name.darkAqua` match): `"atom-one-dark"`
- Light mode: `"atom-one-light"`
- Detected via `NSApp.effectiveAppearance.bestMatch(from:)`
- An `NSKeyValueObservation` watches `NSApp.effectiveAppearance` and re-highlights on change.

### Debouncing

Highlighting is debounced at **150ms** using `DispatchWorkItem` on the main queue. Each keystroke cancels the previous work item and schedules a new one.

### Large File Guard

Files larger than **1 MB** skip syntax highlighting entirely.

### Highlight Application

1. `Highlighter.highlight(code, as: language)` returns an `NSAttributedString`.
2. If `language` is `nil`, highlight.js auto-detects the language.
3. The attributed string is set on `textStorage`, then:
   - Font is re-applied (monospaced, 13pt).
   - Paragraph style (2pt line spacing) is re-applied.
   - Cursor position (`selectedRange`) is restored.
   - Scroll position is preserved.

## Line Number Gutter

### File: `LineNumberGutterView.swift`

A custom `NSView` subclass that draws line numbers.

| Property | Value |
|----------|-------|
| Width | 44pt fixed |
| Font | Monospaced digit system font, (fontSize - 1)pt |
| Color | `.secondaryLabelColor` |
| Alignment | Right-aligned with 8pt right margin |
| Background | `.controlBackgroundColor` |
| Separator | 0.5pt line at right edge, `.separatorColor` |
| Coordinate system | Flipped (origin at top-left) |

### Drawing Algorithm

1. Fill background.
2. Draw right-edge separator.
3. Get the visible rect from the enclosing scroll view.
4. Enumerate line fragments from the layout manager.
5. For each fragment whose origin falls within the visible rect, draw the line number right-aligned.

### Update Triggers

- `NSText.didChangeNotification` (text edits)
- `NSView.boundsDidChangeNotification` (scrolling)

Both trigger `setNeedsDisplay(true)`.

## Word Wrap

Toggled via View > Toggle Word Wrap (⌘⇧↩). Implemented in `applyWordWrap(_:to:scrollView:)`:

| Word Wrap | `containerSize.width` | `widthTracksTextView` | Horizontal scroller |
|-----------|-----------------------|-----------------------|---------------------|
| On | `scrollView.contentSize.width` | `true` | Hidden |
| Off | `CGFloat.greatestFiniteMagnitude` | `false` | Visible |

When word wrap is off the text container is effectively unbounded horizontally, allowing lines to extend beyond the visible area.

## Mini-Map

### File: `MiniMapView.swift`

An `NSView` subclass drawn entirely in Core Graphics. Sits in a fixed 80pt-wide column on the right edge of the editor, toggled via View > Toggle Mini-Map (⌘⇧M).

| Property | Value |
|----------|-------|
| Width | 80pt fixed (hidden: 0pt constraint) |
| Coordinate system | Flipped (origin top-left) |
| Max slot height | 2.5pt per logical line |
| Line cap | 5000 logical lines |

### Drawing Pipeline

Each `draw(_:dirtyRect:)` call executes four passes:

1. **Background & separator** — fills with the text view's background colour; draws a 0.5pt left separator.
2. **Pass 1 — width normalisation** — enumerates all line fragments to find `maxLineWidth` (the widest logical line's `usedRect.width`). This is the normalization denominator, which correctly handles both word-wrap modes (including `CGFloat.greatestFiniteMagnitude` container widths).
3. **Pass 2 — line bars** — for each logical-line-start fragment, draws one horizontal bar whose width is `usedRect.width / maxLineWidth × usableWidth`. Each bar is subdivided into coloured segments mirroring the text storage's `foregroundColor` attribute runs (syntax highlight colours at 75% alpha).
4. **Selection overlay** — tints every line slot that overlaps the current text selection using `NSColor.selectedTextBackgroundColor` at 45% / 35% alpha (dark / light).
5. **Viewport rect** — draws a semi-transparent overlay showing which portion of the document is currently visible.

### Update Triggers

| Event | Trigger |
|-------|---------|
| Scroll | `NSView.boundsDidChangeNotification` on the scroll view's clip view |
| Text change | `miniMapView.needsDisplay = true` in `textDidChange(_:)` |
| Selection change | `miniMapView.needsDisplay = true` in `textViewDidChangeSelection(_:)` |
| Highlighting applied | `miniMapView.needsDisplay = true` after `textStorage.setAttributedString` |

### Click / Drag Navigation

Mouse events convert the click Y-coordinate to a fraction of `miniMapContentHeight` (= `logicalLineCount × slotHeight`) and scroll the text view to the corresponding position in the document.

## Coordinator

The `Coordinator` class is the `NSTextViewDelegate` and manages:

| Responsibility | Method |
|----------------|--------|
| Text changes | `textDidChange(_:)` -- updates binding, cursor state, schedules highlighting, redraws mini-map |
| Selection changes | `textViewDidChangeSelection(_:)` -- updates `EditorState.updateCursor()`, redraws mini-map |
| Key commands | `textView(_:doCommandBy:)` -- Tab and Shift+Tab handling |
| Appearance changes | `NSKeyValueObservation` on `NSApp.effectiveAppearance` |

### Feedback Loop Prevention

A boolean flag `isUpdatingFromTextView` prevents `updateNSView` from overwriting the text view's content while the coordinator is processing a text change from the user.
