# ADR-0015: FSEventStream for Recursive File Tree Watching

## Status

Accepted

## Context

ADR-0005 chose kqueue (via `DispatchSource.makeFileSystemObjectSource`) for file system watching. The original implementation opened a single kqueue file descriptor on the root directory and called `rebuildTree()` on any event.

kqueue fires `NOTE_WRITE` only on the *watched descriptor itself*. Creating a file in a subdirectory (e.g., `src/newfile.swift`) fires a write event on the `src/` directory — not on the root directory. Because only the root was watched, no event arrived at `FileTreeModel` and the tree stayed stale. The limitation was documented in the spec but not fixed until now.

This decision does not affect `TabManager`, which uses kqueue to watch individual *open* files. Single-file watching is precisely what kqueue is suited for, and that code is unchanged.

## Decision

Replace the single-directory kqueue watcher in `FileTreeModel` with `FSEventStream` (CoreServices):

- `FSEventStreamCreate` with the root path watches the entire subtree recursively.
- A 300 ms latency parameter coalesces rapid bursts (e.g., `git checkout`) into a single `rebuildTree()` call.
- `FSEventStreamSetDispatchQueue(.main)` delivers events on the main queue, matching the previous behaviour.
- `kFSEventStreamCreateFlagUseCFTypes` is set; `kFSEventStreamCreateFlagFileEvents` is intentionally omitted — directory-level granularity is sufficient since we call `rebuildTree()` regardless.

## Consequences

**Positive**
- New, renamed, and deleted files anywhere in the project tree now appear in / disappear from the sidebar automatically.
- FSEvents is the Apple-recommended API for recursive directory monitoring and is used by Finder and Xcode.
- The 300 ms coalescing latency avoids a rebuild storm during bulk file operations.

**Negative**
- `CoreServices` must be imported (minor).
- FSEvents has slightly higher initial overhead than a single kqueue fd, but this is negligible in practice.
- Events are coalesced with up to 300 ms latency (vs. near-instant for kqueue). This is an acceptable trade-off for correctness.
