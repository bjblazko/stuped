# ADR-0005: kqueue for File Watching

## Status

Accepted

## Context

The file tree sidebar needs to reflect file system changes (create, rename, delete) in real time. Options:

1. **FSEvents**: high-level macOS API for recursive directory monitoring. Coarse-grained, some latency.
2. **kqueue / DispatchSource**: low-level kernel event queue. Fine-grained, immediate, well-integrated with GCD.
3. **Polling**: simple but wasteful and laggy.

## Decision

Use `DispatchSource.makeFileSystemObjectSource` (kqueue wrapper) to watch the root directory:

```swift
let fd = open(url.path, O_EVTONLY)
let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: fd,
    eventMask: [.write, .rename, .delete, .link],
    queue: .main
)
```

On any event, the entire tree is rebuilt from scratch.

## Consequences

### Positive

- Immediate notification of file system changes.
- Built into GCD, no external dependencies.
- Runs on main queue, so tree updates are automatically thread-safe.

### Negative

- Only watches the root directory, not subdirectories. Changes inside nested directories are not detected unless they affect the root directory's metadata.
- Full tree rebuild on every event. For very large directories this could be expensive, but in practice (typical project sizes) it is fast enough.
- File descriptor is held open for the lifetime of the watcher; must be closed in `deinit`.
