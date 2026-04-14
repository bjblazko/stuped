# Specification: Document Model

## File: `Stuped/Models/StupedDocument.swift`

## Overview

`StupedDocument` conforms to SwiftUI's `FileDocument` protocol, enabling the app to participate in the macOS document lifecycle (open, save, auto-save, revert).

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `text` | `String` | The file's text content |
| `fileURL` | `URL?` | Path to the file on disk (set by the system) |

## Readable Content Types

The document registers as an editor for these `UTType`s:

- `.plainText`
- `.sourceCode`
- `.json`
- `.xml`
- `.yaml`
- `.html`
- `.shellScript`
- `.data`

## Writable Content Types

Same as readable, minus `.data` (binary files are not written back).

## Reading Behavior

1. Extract `regularFileContents` from the `FileWrapper`.
2. **Binary detection**: scan the first 8192 bytes for null (`0x00`) bytes. If found, set `text` to an empty string and return (the view layer shows `"[Binary file -- cannot display]"`).
3. Decode the data as UTF-8 using `String(decoding:as:)`.

## Writing Behavior

1. Encode `text` as UTF-8 `Data`.
2. Return a `FileWrapper(regularFileWithContents:)`.

## Computed Properties

| Property | Type | Derivation |
|----------|------|------------|
| `fileExtension` | `String` | `fileURL?.pathExtension ?? ""` |
| `isMarkdown` | `Bool` | `LanguageMap.isMarkdown(fileExtension)` |
| `previewType` | `PreviewType?` | `LanguageMap.previewType(for: fileExtension)` |
| `isPreviewable` | `Bool` | `previewType != nil` |
| `detectedLanguage` | `String?` | `LanguageMap.language(for: fileExtension)` |
| `isBinary` | `Bool` | `text.isEmpty && fileURL != nil` |

## Default State

A new, untitled document is created with `text = ""` and `fileURL = nil`.
