# ADR-0008: Debounced Rendering

## Status

Accepted

## Context

Both syntax highlighting and preview rendering are expensive operations triggered by every keystroke. Without throttling, typing in a large file would cause visible lag and high CPU usage.

## Decision

Use a debounce pattern with `DispatchWorkItem` on the main queue. Each new keystroke cancels the previous work item and schedules a new one with a delay:

```swift
renderWorkItem?.cancel()
let workItem = DispatchWorkItem { [weak self] in
    self?.executeRender()
}
renderWorkItem = workItem
DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
```

### Delay values

| Component | Delay | Rationale |
|-----------|-------|-----------|
| Syntax highlighting | 150ms | Fast enough to feel responsive, slow enough to batch rapid keystrokes |
| Preview rendering | 300ms | Preview is more expensive (JS evaluation in a separate process); slightly longer delay is acceptable since users watch the editor, not the preview, while typing |

## Consequences

### Positive

- Typing remains smooth regardless of file size or preview complexity.
- CPU usage stays low during rapid editing.
- Simple implementation (~10 lines per debounce site).

### Negative

- Visible delay between typing and highlighting/preview update (150-300ms).
- Not incremental: the entire file is re-highlighted / re-rendered on each debounce fire. For very large files this could still be slow (mitigated by the 1 MB highlighting cap).
- Work items retain `self` weakly, so cancelled renders may leave stale state if the view is deallocated mid-flight (unlikely in practice).
