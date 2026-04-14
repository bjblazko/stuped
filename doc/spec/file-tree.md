# Specification: File Tree

## Files

- `Stuped/Models/FileTreeModel.swift`
- `Stuped/Models/FileNode.swift`
- `Stuped/Views/Sidebar/FileTreeSidebar.swift`

## FileNode

A value type representing a single entry in the file tree.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `URL` | Unique identifier (the file URL) |
| `name` | `String` | Display name (last path component) |
| `url` | `URL` | Full file system URL |
| `isDirectory` | `Bool` | `true` for directories |
| `children` | `[FileNode]?` | Child nodes; `nil` for files |

### Conformances

- `Identifiable` (keyed by `url`)
- `Hashable` and `Equatable` (based on `url`)

### Icon Mapping

`iconName: String` returns an SF Symbol based on file extension:

| Extension(s) | Icon |
|--------------|------|
| `swift` | `swift` |
| `sh, bash, zsh, fish` | `terminal` |
| `html, htm, css, scss` | `globe` |
| `js, jsx, ts, tsx` | `paintpalette` |
| `json, yaml, yml, toml, xml` | `doc.badge.gearshape` |
| `py` | `doc.fill` |
| `md, markdown` | `doc.richtext` |
| `zip, tar, gz, rar, 7z` | `archivebox` |
| `sql, db, sqlite` | `cylinder` |
| Directories | `folder.fill` |
| Everything else | `doc` |

## FileTreeModel

An `@Observable` class that builds and watches a directory tree.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `rootNode` | `FileNode?` | Root of the tree |
| `rootURL` | `URL?` | Root directory path |
| `showHiddenFiles` | `Bool` | Include hidden files (default: `false`) |

### Building the Tree

`loadDirectory(at:)`:

1. Stores the `rootURL`.
2. Calls `rebuildTree()` to build `rootNode` recursively.
3. Calls `startWatching(url:)` to monitor changes.

`buildNode(at:)`:

1. Checks if the URL is a directory.
2. For directories: recursively builds children via `buildChildren(at:)`.
3. For files: creates a leaf `FileNode` with `children: nil`.

`buildChildren(at:)`:

1. Lists directory contents via `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`.
2. Filters hidden files if `showHiddenFiles` is `false` (uses both `.skipsHiddenFiles` option and explicit `isHidden` check).
3. Recursively builds child nodes.
4. Sorts: directories first, then alphabetical by name (case-insensitive, using `localizedCaseInsensitiveCompare`).

### File Watching

Uses Darwin kqueue via `DispatchSource.makeFileSystemObjectSource`:

1. Opens the directory with `open(path, O_EVTONLY)`.
2. Monitors events: `.write`, `.rename`, `.delete`, `.link`.
3. On any event: calls `rebuildTree()` on the main queue.
4. On cancel: closes the file descriptor.
5. `stopWatching()` cancels the dispatch source and is called in `deinit` and before starting a new watch.

### Limitations

- Watches only the root directory, not subdirectories.
- Rebuilds the entire tree on any change (no incremental updates).
- Does not debounce rapid file system events.

## FileTreeSidebar

A SwiftUI `List` with `.sidebar` style.

### Behavior

- Displays `rootNode.children` using SwiftUI's `List(_:children:selection:)` for hierarchical display.
- Each row: `Label(node.name, systemImage: node.iconName)`.
- Selection binding: `@Binding selectedFileURL: URL?`, tagged with `node.url`.
- Shows `ContentUnavailableView` if no root node or empty children.
