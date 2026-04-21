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
| `html, htm, xhtml` | `globe` |
| `css, scss, sass, less` | `paintpalette` |
| `json` | `curlybraces` |
| `xml, plist, svg` | `chevron.left.forwardslash.chevron.right` |
| `md, markdown, mdown, mkd, mdx` | `doc.richtext` |
| `sh, bash, zsh, fish` | `terminal` |
| `yml, yaml, toml, ini, cfg, conf, env, properties` | `gearshape` |
| `png, jpg, jpeg, gif, webp, heic, ico, bmp, tiff` | `photo` |
| `pdf` | `doc.fill` |
| `zip, tar, gz, bz2, 7z, rar` | `archivebox` |
| `sql` | `cylinder` |
| `dockerfile, docker` | `shippingbox` |
| Directories | `folder.fill` |
| Everything else | `doc` |

### Icon Colors

`iconColor: Color` returns a SwiftUI `Color` for the icon, mapped by language/format group:

| Color | Extensions |
|-------|-----------|
| `.red` | `swift`, `rs` |
| `.orange` | `py`, `html`, `htm`, `xhtml`, `java` |
| `.yellow` | `js`, `mjs`, `jsx`, `ts`, `tsx`, `json` |
| `.green` | `go`, `sh`, `bash`, `zsh`, `fish`, `bat`, `cmd`, `ps1`, `psm1` |
| `.mint` | `md`, `markdown`, `rst`, `tex`, `latex` |
| `.teal` | `css`, `scss`, `sass`, `less` |
| `.cyan` | `xml`, `plist`, `yml`, `yaml`, `toml`, `ini`, `cfg`, `conf`, `env` |
| `.blue` | `c`, `h`, `cpp`, `cc`, `cxx`, `hpp`, `hxx`; directories |
| `.indigo` | `kt`, `kts`, `scala`, `groovy`, `gradle`, `clj`, `erl`, `hrl` |
| `.purple` | `rb`, `php`, `pl`, `pm`, `lua`, `ex`, `exs`, `hs`, `lhs`, `ml`, `lisp` |
| `.pink` | `png`, `jpg`, `jpeg`, `gif`, `svg`, `webp`, `heic`, `ico`, `bmp`, `tiff` |
| custom red | `sql` |
| `.orange` | `dockerfile`, `makefile`, `cmake` |
| `.secondary` | everything else |

## FileTreeModel

An `@Observable` class that builds and watches a directory tree.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `rootNode` | `FileNode?` | Root of the tree |
| `rootURL` | `URL?` | Root directory path |
| `showHiddenFiles` | `Bool` | Include hidden files (default: `false`) |
| `expandedURLs` | `Set<URL>` | Directory URLs currently expanded in the sidebar |
| `selectedItemURL` | `URL?` | Currently selected file-tree item (file or folder) |
| `pendingCreation` | `PendingFileTreeCreation?` | Inline draft item being named under the selected directory |

### Building the Tree

`loadDirectory(at:)`:

1. Stores the `rootURL`.
2. Resets `expandedURLs` to contain the root folder so the first level stays visible.
3. Clears the selected tree item and any pending inline create draft.
4. Calls `rebuildTree()` to build `rootNode` recursively.
5. Calls `startWatching(url:)` to monitor changes.

Selection and creation state:

- `selectItem(_:)` tracks the current sidebar selection independently from the active editor tab so folders can become explicit action targets.
- `selectedDirectoryURL` / `canCreateInSelectedDirectory` only resolve to `true` when the current tree selection is a directory.
- `beginCreation(kind:)` expands the selected directory and creates one `PendingFileTreeCreation` draft row under it.
- `commitPendingCreation()` validates the name, creates either an empty file or a directory on disk, clears the draft, selects the new item, and issues a reveal request so the created row stays visible.
- `cancelPendingCreation()` removes the inline draft row without touching the file system.

`expandToURL(_ targetURL: URL)`:

Adds all ancestor directories between `rootURL` and `targetURL` (inclusive of `rootURL`) to `expandedURLs`. Used by "Reveal in File Tree" to programmatically expand the path to a given file.

`reveal(_ targetURL: URL)`:

Expands the ancestor path via `expandToURL(_:)`, records the file URL as the current reveal target, and increments a reveal request counter so the sidebar can scroll that row into view after the lazy tree rebuild completes.

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

Uses `FSEventStream` (CoreServices) for recursive directory watching (ADR-0015):

1. `FSEventStreamCreate` is called with the root URL path, a 300 ms latency, and `kFSEventStreamCreateFlagUseCFTypes`.
2. The stream is scheduled on `DispatchQueue.main` via `FSEventStreamSetDispatchQueue`.
3. On any event (file/directory created, renamed, deleted, modified anywhere in the tree): calls `rebuildTree()`.
4. `stopWatching()` stops, invalidates, and releases the stream; called in `deinit` and before starting a new watch.

The 300 ms latency coalesces rapid bursts (e.g., `git checkout` touching many files) into a single `rebuildTree()` call.

### Limitations

- Rebuilds the entire tree on any change (no incremental updates).
- `expandedURLs` is reset to `[]` when `loadDirectory(at:)` is called (fresh folder open starts collapsed).

> **See also:** `TabManager` uses kqueue/DispatchSource to watch individual *open* files and reload their content when an external process writes to them (ADR-0013). The two watching mechanisms serve different purposes and coexist.

## FileTreeSidebar

A SwiftUI `List` with `.sidebar` style rendered via explicit `DisclosureGroup` expansion.

### Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `rootNode` | `FileNode?` | Tree root from `FileTreeModel` |
| `selectedFileURL` | `Binding<URL?>` | Currently selected file |
| `expandedURLs` | `Binding<Set<URL>>` | Directories currently expanded |
| `projectRootURL` | `URL?` | Originally opened project root used for relative-path copy actions |

### Behavior

- Displays `rootNode.children` in a `.sidebar` `List` wrapped in `ScrollViewReader`, using a recursive private view `FileTreeRows`.
- Each directory node is rendered as a `DisclosureGroup` whose `isExpanded` binding reads from and writes to `expandedURLs`. Clicking a folder expands/collapses it and also selects it as the current file-tree target. Programmatic reveal updates the set via `FileTreeModel.reveal(_:)`, which expands ancestors and issues a scroll request for the target file row.
- Each file node is rendered as a tappable `Label`; tapping it updates both the tree selection and `selectedFileURL`, which drives folder-mode tab opening in `ContentView`.
- Each label shows `Text(node.name)` and a tinted `Image(systemName: node.iconName).foregroundStyle(node.iconColor)`.
- Each row uses its file URL as a stable identity so the sidebar can programmatically scroll to the revealed node and center it in view.
- File and folder rows expose a `Copy Path` context submenu with `Name Only`, `Relative to Project Root`, and `Full Path` actions.
- When the current tree selection is a folder, the same context menu also enables `New File` and `New Folder` actions.
- Starting a create action inserts a transient inline `TextField` row under the selected directory at the same position the final item will occupy after sorting (directories first, then case-insensitive name order).
- Pressing `Return` creates the item; pressing `Escape` cancels the draft row.
- Relative paths are derived from the originally opened project root (`FolderBrowserState.folderURL`), not the currently narrowed tree root.
- Shows `ContentUnavailableView` if no root node or empty children.

> **ADR-0014**: The sidebar switched from `List(_:children:selection:)` (auto-managed expansion) to explicit `DisclosureGroup` to support programmatic expansion for the "Reveal in File Tree" feature.
