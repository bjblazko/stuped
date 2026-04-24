# ADR-0015: FSEventStream for Recursive File Tree Watching

## Status

Accepted

## Context

ADR-0005 chose kqueue (via `DispatchSource.makeFileSystemObjectSource`) for file system watching. The original implementation opened a single kqueue file descriptor on the root directory and called `rebuildTree()` on any event.

kqueue fires `NOTE_WRITE` only on the *watched descriptor itself*. Creating a file in a subdirectory (e.g., `src/newfile.swift`) fires a write event on the `src/` directory — not on the root directory. Because only the root was watched, no event arrived at `FileTreeModel` and the tree stayed stale. The limitation was documented in the spec but not fixed until now.

This decision does not affect `TabManager`, which uses kqueue to watch individual *open* files. Single-file watching is precisely what kqueue is suited for, and that code is unchanged.

Later idle-CPU profiling showed that switching to FSEvents alone was not enough for noisy repositories: even filtered structural callbacks could still arrive in dense bursts and repeatedly drive `FileTreeModel.rebuildTree()` on the main queue. In one representative project this showed up as sustained high idle CPU until rebuild execution itself was coalesced.

## Decision

Replace the single-directory kqueue watcher in `FileTreeModel` with `FSEventStream` (CoreServices):

- `FSEventStreamCreate` with the root path watches the entire subtree recursively.
- A 300 ms latency parameter coalesces rapid bursts (e.g., `git checkout`) into a single `rebuildTree()` call.
- `FSEventStreamSetDispatchQueue(.main)` delivers events on the main queue, matching the previous behaviour.
- `kFSEventStreamCreateFlagUseCFTypes` and `kFSEventStreamCreateFlagFileEvents` are set. 
- Path-and-flag-aware rebuilds: the model only triggers a tree rebuild for **structural** events (`created`, `removed`, `renamed`, `rootChanged`) whose direct parent directory is currently expanded; content-only writes no longer rebuild the sidebar.
- Filesystem-triggered rebuild execution is trailing-edge debounced inside the model, so repeated callbacks from one noisy burst collapse to one `rebuildTree()` pass.
- Git decoration refreshes are emitted separately from tree rebuilds so working-tree badges can stay current without forcing a full sidebar rebuild.


## Consequences

**Positive**
- New, renamed, and deleted files anywhere in the project tree now appear in / disappear from the sidebar automatically.
- FSEvents is the Apple-recommended API for recursive directory monitoring and is used by Finder and Xcode.
- The 300 ms coalescing latency avoids a rebuild storm during bulk file operations.
- A second rebuild-level debounce further reduces main-thread churn when the same project path generates repeated FSEvents callbacks while the visible tree has not materially changed between them.
- Working-tree badge refresh remains responsive without tying every file-content event to a tree rebuild.
- Follow-up validation on the representative project brought idle CPU back down into roughly the 3-8% range, which confirmed that callback-level rebuild churn had been a real remaining hotspot.

**Negative**
- `CoreServices` must be imported (minor).
- FSEvents has slightly higher initial overhead than a single kqueue fd, but this is negligible in practice.
- Events are coalesced with up to 300 ms latency (vs. near-instant for kqueue). This is an acceptable trade-off for correctness.
