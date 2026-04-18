# ADR-0014: Explicit DisclosureGroup for File Tree Expansion

## Status

Accepted

## Context

The file tree sidebar originally used SwiftUI's `List(_:children:selection:)` API, which automatically manages expand/collapse state for hierarchical data. This is the simplest approach and required no custom expansion logic.

Adding "Reveal in File Tree" (a feature that programmatically expands the path to the active file) exposed a fundamental limitation: SwiftUI's `List(children:)` does not expose any API to programmatically expand a specific node or set of nodes. The internal expansion state is entirely owned by the `List` and cannot be read or written from outside.

## Decision

Replace `List(_:children:selection:)` with a `List(selection:)` containing a recursive private view (`FileTreeRows`) that renders directory nodes as `DisclosureGroup` views with an explicit `isExpanded: Binding<Bool>` derived from a `Set<URL>` (`expandedURLs`) owned by `FileTreeModel`.

- User clicks on a disclosure triangle read/write `expandedURLs` directly via the binding — identical UX to before.
- `FileTreeModel.expandToURL(_:)` can add ancestor URLs to `expandedURLs` before setting the selection, achieving programmatic expansion.
- `expandedURLs` is reset to `[]` when a new folder is loaded, so fresh opens start fully collapsed.

## Consequences

**Positive**
- Enables programmatic expansion for "Reveal in File Tree" and any future navigation features.
- Expansion state is observable and testable — it's plain `Set<URL>` on a model object.
- User-controlled expand/collapse still works naturally through the `DisclosureGroup` binding.

**Negative**
- Slightly more code than the single-line `List(children:)` call.
- SwiftUI's built-in indent and disclosure triangle styling is preserved, but the implementation is now manual and must track state that was previously implicit.
- `expandedURLs` is lost when `loadDirectory(at:)` is called (intentional reset).
