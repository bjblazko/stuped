# ADR-0013: Per-Tab File Watching for External Change Detection

**Status:** Accepted  
**Date:** 2026-04-15

## Context

`TabManager` caches each open file's content in `TabItem.text`. When an external process (e.g. another editor, a code generator, or a build tool) writes to a file that is currently open in a tab, the editor continued to show the stale cached content. The only workaround was to close the tab and reopen the file.

`FileTreeModel` (ADR-0005) already watches the root directory with kqueue to keep the sidebar tree current, but it only monitors directory metadata events — it does not reload individual file contents.

## Decision

Extend `TabManager` with per-tab DispatchSource file watchers that mirror the pattern used in `FileTreeModel`:

- When a new tab is created, open the file with `O_EVTONLY` and create a `DispatchSourceFileSystemObject` monitoring `.write`, `.rename`, and `.delete` events.
- On `.write`: if the tab is not dirty (`!tab.isDirty`), reload the file text via `TabManager.loadText(from:)` and update both `tab.text` and `tab.savedText`. Because `TabItem` is `@Observable`, SwiftUI propagates the change to the editor automatically.
- On `.rename` or `.delete`: cancel the watcher (the file path is no longer valid).
- When a tab is closed or all tabs are cleared, cancel and remove the corresponding watcher.

Dirty tabs (those with unsaved user edits) are never overwritten; external changes are silently dropped for them.

## Alternatives Considered

**Reload on tab switch** — reload from disk every time a tab is activated. Simple, but introduces a visible flicker and loses the user's scroll/cursor position on every switch.

**Reload on app focus change** — reload when the app becomes active. Misses changes while the app is in the foreground (common when Claude or a terminal is writing to a file).

**Polling** — periodic timer to stat each open file's modification time and reload if changed. Works but wastes CPU, has latency proportional to the interval, and requires an additional timer per tab or a shared scan loop.

## Consequences

- Each open tab holds one additional file descriptor (`O_EVTONLY`) for the lifetime of the tab. The OS limit on open file descriptors (default 256 per process, soft; 10240, hard) is not a practical concern for typical numbers of open tabs.
- The watcher runs on `.main`, so UI updates are thread-safe without additional synchronization.
- External writes to dirty tabs are silently ignored. A future iteration could show a banner ("File changed on disk — discard your edits?"), but the silent-skip behavior is safe and matches common editor defaults.
