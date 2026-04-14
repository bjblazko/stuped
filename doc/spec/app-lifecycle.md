# Specification: App Lifecycle

## File: `Stuped/StupedApp.swift`

## Scenes

The app defines two scenes:

### 1. DocumentGroup (single-file editing)

```swift
DocumentGroup(newDocument: StupedDocument()) { file in
    ContentView(document: file.$document, fileURL: file.fileURL)
}
```

- Handles files opened via Finder, File > Open, or File > New.
- Each document gets its own window with its own `ContentView`.
- Uses default launch behavior; the open/recent dialog is suppressed via `applicationShouldOpenUntitledFile` returning `true` (which creates a blank document on cold launch instead of showing the dialog).

### 2. Window (folder browsing)

```swift
Window("Stuped -- Folder", id: "folder-browser") {
    FolderBrowserView()
}
.defaultSize(width: 900, height: 600)
```

- Opened via Open Folder (Cmd+Shift+O).
- Single shared window (not a WindowGroup).

## AppDelegate

```swift
class AppDelegate: NSObject, NSApplicationDelegate
```

- `applicationShouldOpenUntitledFile(_:)`: returns `true`, which creates a blank document on cold launch instead of showing the open/recent dialog.

## Launch Flow

1. App starts, SwiftUI creates scenes.
2. If no file is being opened (cold launch), `applicationShouldOpenUntitledFile` returns `true`, creating a blank editor window.
3. If a file is being opened (e.g. from Finder), DocumentGroup handles it directly and opens the file in a new window.

## Single-File Mode vs Folder Mode

### Single-file mode

- Created by `DocumentGroup` when a file is opened.
- `ContentView(document:fileURL:)` -- `isFolderMode = false`.
- `activeFileURL` returns `fileURL` (set by the system).
- Sidebar hidden by default (`.detailOnly`).
- `setupFileTree()` loads the parent directory of the opened file into the sidebar tree and selects the file.

### Folder mode

- Created by the `Window` scene via `FolderBrowserView`.
- `ContentView(document:fileURL:folderMode: true)` -- `isFolderMode = true`.
- `activeFileURL` returns `sidebarFileURL` (selected in sidebar).
- Sidebar visible by default (`.all`).
- `setupFileTree()` is a no-op; the tree is loaded via `.stupedFolderOpened` notification.

## Folder Opening Flow

1. User triggers Cmd+Shift+O.
2. `StupedApp.openFolder()` shows `NSOpenPanel` for directory selection.
3. On success: `FolderBrowserState.shared.openFolder(url:)` stores the URL.
4. `openWindow(id: "folder-browser")` activates the folder-browser window.
5. `FolderBrowserView` observes `folderState.folderURL` change.
6. Posts `Notification.Name.stupedFolderOpened` with `["url": url]`.
7. `ContentView` receives the notification, calls `treeModel.loadDirectory(at:)`.

## FolderBrowserState

A singleton `@Observable` class:

```swift
@Observable
class FolderBrowserState {
    static let shared = FolderBrowserState()
    var folderURL: URL?
}
```

Bridges the `StupedApp` scene (which has access to `openWindow`) with the `FolderBrowserView` (which needs the folder URL).

## File Loading in Folder Mode

When a file is selected in the sidebar (`onChange(of: sidebarFileURL)`):

1. Verify the file exists and is not a directory.
2. Read file data from disk.
3. Check for binary content (null bytes in first 8 KB).
4. Decode as UTF-8 into `document.text`.
5. Detect line endings and indentation.
6. Set `viewMode` to `.split` if previewable, else `.edit`.
7. Refresh git info.

## Saving in Folder Mode

- No visible save button (removed from toolbar).
- Cmd+S is registered via a hidden zero-size `Button` with `.keyboardShortcut("s")`.
- `saveCurrentFile()` writes `document.text` to `sidebarFileURL` via `String.write(to:atomically:encoding:)`.
