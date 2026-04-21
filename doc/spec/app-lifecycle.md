# Specification: App Lifecycle

## File: `Stuped/StupedApp.swift`

## Scenes

The app defines two scenes:

### 1. DocumentGroup (single-file editing)

```swift
DocumentGroup(newDocument: StupedDocument()) { file in
    ContentView(document: file.$document, fileURL: file.fileURL)
        .windowFullScreenBehavior(.enabled)
}
```

- Handles files opened via Finder, File > Open, or File > New.
- Each document gets its own window with its own `ContentView`.
- Uses SwiftUI's native macOS full-screen interaction so the green traffic-light button enters full screen.
- Uses custom launch behavior; the open/recent dialog is suppressed via `applicationShouldOpenUntitledFile` returning `false`, and `applicationDidFinishLaunching(_:)` creates a blank document window on cold launch when needed.

### 2. WindowGroup (folder browsing)

```swift
WindowGroup("Stuped — Folder", id: "folder-browser", for: String.self) { _ in
    FolderBrowserView()
        .windowFullScreenBehavior(.enabled)
} defaultValue: {
    "main"
}
.defaultSize(width: 900, height: 600)
```

- Opened via Open Folder (Cmd+Shift+O).
- Declared as a `WindowGroup` so it gets standard macOS window management, including native fullscreen behavior.
- Reused as a single logical folder window by always opening the group with the same presentation value (`"main"`).
- Uses SwiftUI's native macOS full-screen interaction so the green traffic-light button enters full screen.
- `FolderBrowserView` owns a `TabManager` and passes an `activeDocumentBinding` to `ContentView` so save commands still route through the active tab's text, while each open tab keeps its own mounted `DocumentPaneView`.
- Folder opens are recorded in `RecentFoldersStore`, which powers Stuped's own `Recent Folders` menu and the folder-mode Cmd+R recent-items popup; this is app-managed history, while file recents still come from `NSDocumentController`.

### 3. Window (About)

```swift
Window("About Stuped", id: "about") {
    AboutView()
}
.windowResizability(.contentSize)
```

- Opened via the Stuped > About Stuped menu item (intercepted via `CommandGroup(replacing: .appInfo)`).
- Displays version, copyright, and links to the website, GitHub, and the Apache 2.0 license.

## AppDelegate

```swift
class AppDelegate: NSObject, NSApplicationDelegate
```

- `applicationShouldOpenUntitledFile(_:)`: returns `false`, which suppresses the system open/recent dialog. `applicationDidFinishLaunching(_:)` then creates a blank document window on cold launch when no documents were opened.

## Launch Flow

1. App starts, SwiftUI creates scenes.
2. If no file is being opened (cold launch), `applicationShouldOpenUntitledFile` returns `false`, suppressing the system open/recent dialog.
3. `applicationDidFinishLaunching(_:)` creates a blank editor window if no documents were opened by the system.
4. If a file is being opened (e.g. from Finder), DocumentGroup handles it directly and opens the file in a new window.

## Single-File Mode vs Folder Mode

### Single-file mode

- Created by `DocumentGroup` when a file is opened.
- `ContentView(document:fileURL:)` -- `isFolderMode = false`.
- Uses the same `DocumentPaneView` building block as folder mode, but with a single session and no tab strip.
- `activeFileURL` returns `fileURL` (set by the system).
- Sidebar hidden by default (`.detailOnly`).
- `setupFileTree()` loads the parent directory of the opened file into the sidebar tree and selects the file.

### Folder mode

- Created by the folder `WindowGroup` via `FolderBrowserView`.
- `ContentView(document:fileURL:folderMode: true)` -- `isFolderMode = true`.
- `activeFileURL` returns `sidebarFileURL` (selected in sidebar).
- Sidebar visible by default (`.all`).
- `setupFileTree()` is a no-op; the tree is loaded via `.stupedFolderOpened` notification.

## Folder Opening Flow

1. User triggers Cmd+Shift+O.
2. `StupedApp.openFolder()` shows `NSOpenPanel` for directory selection.
3. On success: `FolderBrowserState.shared.openFolder(url:)` normalizes the URL, records it in `RecentFoldersStore`, and stores it as the active folder root.
4. `openWindow(id:value:)` opens or re-activates the folder-browser window using the fixed presentation value `"main"`.
5. `FolderBrowserView` observes `folderState.folderURL` change.
6. Posts `Notification.Name.stupedFolderOpened` with `["url": url]`.
7. `ContentView` receives the notification, calls `treeModel.loadDirectory(at:)`.

## FolderBrowserState

A singleton `@Observable` class that bridges `StupedApp` (which has `openWindow`) with `FolderBrowserView`:

```swift
@Observable
class FolderBrowserState {
    static let shared = FolderBrowserState()
    var folderURL: URL?
    var selectedFileURL: URL?   // drives the window title
}
```

`openFolder(url:)` also resets `treeRootURL`, clears the selected file, and updates the recent-folders history used by Stuped-owned folder recents UI.

## Tab Management in Folder Mode

`FolderBrowserView` owns a `TabManager` instance. File loading is routed through it:

1. Sidebar selection change → `onFileSelected` callback → `TabManager.open(url:)`.
2. `TabManager.open(url:)`: if tab already exists, switches to it and posts `.stupedTabSwitched`; otherwise loads the file from disk, creates a `TabItem`, and makes it active.
3. `FolderBrowserView.activeDocumentBinding` exposes `tabManager.activeTab.text` as a `Binding<StupedDocument>` to `ContentView`.
4. On tab switch, `ContentView` receives `.stupedTabSwitched`, updates `sidebarFileURL` (sidebar highlight), and makes the target tab's already-mounted `DocumentPaneView` visible without re-reading the file from disk.

`TabItem` stores:
- `fileURL` — immutable
- `text` — current editor content
- `savedText` — content as of last save; `isDirty` is computed as `text != savedText`
- `viewMode` — the tab's selected Edit / Split / Preview mode

## File Loading in Folder Mode (new tab)

When `TabManager.open(url:)` creates a new tab:

1. Derive the tab's initial `viewMode` from the file type: images open in `.preview`, previewable text files in `.split`, other text files in `.edit`.
2. Read file data from disk.
3. Check for binary content (null bytes in first 8 KB).
4. Decode as UTF-8; store in `TabItem.text` and `TabItem.savedText`.
5. When the tab's `DocumentPaneView` is first mounted, it creates that tab's editor/preview instances and keeps them alive until the tab is closed.

## Saving in Folder Mode

- Cmd+S is registered via a hidden zero-size `Button` with `.keyboardShortcut("s")`.
- `saveCurrentFile()` writes `document.text` (= active tab's text via binding) to `sidebarFileURL`.
- The `onFileSaved` callback notifies `FolderBrowserView`, which calls `tabManager.activeTab?.markSaved()` to clear the dirty flag.
