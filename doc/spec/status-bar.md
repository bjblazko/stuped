# Specification: Status Bar

## Files

- `Stuped/Views/StatusBarView.swift`
- `Stuped/Models/EditorState.swift`

## StatusBarView

A horizontal bar at the bottom of the editor showing metadata about the current file and cursor.

### Layout (left to right)

1. **Cursor position**: `"Ln {line}, Col {column}"` (1-indexed)
2. Divider
3. **Line count**: `"{count} lines"`
4. Spacer
5. **Language** (if detected): capitalized language name, followed by divider
6. **Indentation** (if detected): `"Tabs"` or `"Spaces: {n}"`, followed by divider
7. **Line ending**: `"LF"`, `"CRLF"`, or `"CR"`
8. Divider
9. **Encoding**: `"UTF-8"`

### Styling

| Property | Value |
|----------|-------|
| Font | System monospaced, 11pt |
| Text color | `.secondary` |
| Horizontal padding | 12pt |
| Vertical padding | 4pt |
| Background | `.bar` |
| Divider height | 12pt |

### Visibility

Hidden when `viewMode == .preview` (preview-only mode shows no status bar).
Hidden for inactive retained tab panes; only the active pane keeps status-bar chrome mounted.

## EditorState

An `@Observable` class tracking editor metadata.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `cursorLine` | `Int` | `1` | Current line (1-indexed) |
| `cursorColumn` | `Int` | `1` | Current column (1-indexed) |
| `lineCount` | `Int` | `1` | Total lines in document |
| `encoding` | `String` | `"UTF-8"` | Always UTF-8 |
| `lineEnding` | `String` | `"LF"` | Detected line ending style |
| `indentStyle` | `String?` | `nil` | Detected indentation |

### Line Ending Detection

`detectLineEnding(in text: String)`:

1. If text contains `\r\n` -> `"CRLF"`.
2. Else if text contains `\r` -> `"CR"`.
3. Else -> `"LF"`.

### Indentation Detection

`detectIndentation(in text: String)`:

1. Scan the first **200 lines**.
2. For each line, check if it starts with a tab or spaces.
3. Count `tabCount` vs `spaceCount`.
4. If tabs dominate: `"Tabs"`.
5. If spaces dominate:
   - Collect the leading space count for each space-indented line.
   - Count how many are divisible by 2 vs by 4.
   - If 4-divisible lines outnumber 2-divisible: `"Spaces: 4"`.
   - Otherwise: `"Spaces: 2"`.
6. If no indentation found: `nil`.

### Cursor Position Tracking

`updateCursor(text: String, selectedRange: NSRange)`:

1. Count newlines in `text[0..<selectedRange.location]` to get the line number.
2. Find the start of the current line.
3. Column = `selectedRange.location - lineStart + 1`.
4. Update `lineCount` by counting total newlines + 1.
