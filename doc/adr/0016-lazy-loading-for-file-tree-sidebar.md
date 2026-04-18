# ADR-0016: Lazy Loading for File Tree Sidebar

## Status

Accepted

## Context

The original file tree implementation was recursive, meaning it crawled every directory and subdirectory in the project project root as soon as a folder was opened. For large projects (e.g., those containing `node_modules` or thousands of source files), this caused significant startup lag, high memory usage, and unresponsive UI during file system updates.

## Decision

Implement "lazy loading" for the file tree:

- `FileTreeModel` only enumerates the contents of the root directory and directories that are explicitly expanded by the user (stored in `expandedURLs`).
- `FileNode` objects for non-expanded directories have `children = nil`.
- The `FileTreeSidebar` uses the `toggleExpansion(for:)` method on the model, which updates the expansion state and triggers a targeted rebuild of the tree.
- `FSEvents` integration is optimized to only trigger a rebuild if a file system change occurs within an expanded path.

## Consequences

**Positive**
- **Performance:** Instant loading even for massive project directories.
- **Memory Efficiency:** Only nodes currently visible (or previously expanded) are kept in memory.
- **Responsiveness:** The app remains snappy when external tools (like AI agents or build scripts) modify files in deep, unexpanded subdirectories.

**Negative**
- Rebuilding the tree is now required on every expand/collapse action (though this is extremely fast due to lazy loading).
- Programmatic expansion (like "Reveal in File Tree") must ensure all ancestor nodes are built during the expansion process.
