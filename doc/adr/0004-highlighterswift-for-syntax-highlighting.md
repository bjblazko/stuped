# ADR-0004: HighlighterSwift for Syntax Highlighting

## Status

Accepted

## Context

The code editor needs syntax highlighting for 100+ programming languages with theme support. Options:

1. **Tree-sitter**: accurate, incremental parsing. Requires per-language grammar binaries and significant integration work.
2. **HighlighterSwift**: Swift wrapper around highlight.js via JavaScriptCore. Simple API, 150+ languages, many themes.
3. **Custom regex-based highlighting**: limited accuracy, high maintenance.

## Decision

Use [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) (SPM dependency, version 1.0.0+).

Integration:

- `Highlighter` instance is created once per coordinator.
- `highlight(code, as: language)` returns an `NSAttributedString`.
- Theme is set based on system appearance: `"atom-one-dark"` (dark) or `"atom-one-light"` (light).
- Highlighting is debounced at 150ms and skipped for files > 1 MB.
- After highlighting, font and paragraph style attributes are re-applied.

## Consequences

### Positive

- Trivial integration: one SPM dependency, three lines of highlighting code.
- Wide language support without maintaining grammars.
- Theme support with light/dark switching.

### Negative

- Not incremental: re-highlights the entire file on each change (mitigated by debouncing and the 1 MB cap).
- JavaScriptCore overhead for each highlight pass.
- Language auto-detection can be wrong; relies on `LanguageMap` to provide the correct language when possible.
