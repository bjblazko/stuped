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

> **See also:** `TabManager` uses the same kqueue/DispatchSource pattern to watch individual open files and reload their content when an external process writes to them (ADR-0013).

## FileTreeSidebar

A SwiftUI `List` with `.sidebar` style.

### Behavior

- Displays `rootNode.children` using SwiftUI's `List(_:children:selection:)` for hierarchical display.
- Each row renders a custom `Label` with `Text(node.name)` and a tinted `Image(systemName: node.iconName).foregroundStyle(node.iconColor)`.
- Selection binding: `@Binding selectedFileURL: URL?`, tagged with `node.url`.
- Shows `ContentUnavailableView` if no root node or empty children.
