# Specification: Code Editor

## Files

- `Stuped/Views/Editor/CodeEditorView.swift`
- `Stuped/Views/Editor/LineNumberGutterView.swift`

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
  +-- NSScrollView (fills remaining width)
        +-- NSTextView
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

## Coordinator

The `Coordinator` class is the `NSTextViewDelegate` and manages:

| Responsibility | Method |
|----------------|--------|
| Text changes | `textDidChange(_:)` -- updates binding, cursor state, schedules highlighting |
| Selection changes | `textViewDidChangeSelection(_:)` -- updates `EditorState.updateCursor()` |
| Key commands | `textView(_:doCommandBy:)` -- Tab and Shift+Tab handling |
| Appearance changes | `NSKeyValueObservation` on `NSApp.effectiveAppearance` |

### Feedback Loop Prevention

A boolean flag `isUpdatingFromTextView` prevents `updateNSView` from overwriting the text view's content while the coordinator is processing a text change from the user.
