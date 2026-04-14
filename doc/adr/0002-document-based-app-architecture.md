# ADR-0002: Document-Based App Architecture

## Status

Accepted

## Context

Stuped needs to open files from Finder, support File > Open / File > New, and participate in the macOS document lifecycle (auto-save, dirty indicators, recent documents). It also needs a separate folder-browsing mode.

## Decision

Use SwiftUI's `DocumentGroup` scene for single-file editing. This provides automatic:

- File type registration via `UTType` in `Info.plist`
- Open/save/revert via `FileDocument` protocol
- Recent documents menu
- Window-per-document model

A separate `Window` scene (id: `"folder-browser"`) hosts the folder-browsing mode, using the same `ContentView` with `isFolderMode = true`.

The launch dialog is suppressed by returning `true` from `applicationShouldOpenUntitledFile`, which creates a blank document on cold launch instead of showing the open/recent dialog. This preserves DocumentGroup's ability to handle file-open requests from Finder.

## Consequences

### Positive

- Standard macOS document behavior with minimal code.
- File type associations work automatically.
- Each file gets its own window and undo stack.

### Negative

- `DocumentGroup` controls the document lifecycle, making it hard to customize (e.g., suppressing the launch dialog required an `AppDelegate` with `applicationShouldOpenUntitledFile`).
- Folder mode cannot use `DocumentGroup` (it manages files manually), requiring a parallel `Window` scene and `NotificationCenter` communication.
- Two `ContentView` initialization paths (single-file vs folder) add conditional complexity.
