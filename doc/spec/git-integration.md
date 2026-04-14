# Specification: Git Integration

## File: `Stuped/Models/GitInfo.swift`

## Overview

`GitInfo` is a plain struct that asynchronously fetches git repository metadata by shelling out to `/usr/bin/git` via `Foundation.Process`.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `branchName` | `String` | Current branch name or short SHA |
| `remoteURL` | `String?` | `remote.origin.url` if configured |
| `repoRoot` | `URL` | Absolute path to repository root |

## Fetching

`static func fetch(for fileURL: URL) async -> GitInfo?`

### Steps

1. Determine the working directory:
   - If `fileURL` is a directory, use it directly.
   - If it's a file, use `deletingLastPathComponent()`.

2. Run `git rev-parse --show-toplevel`:
   - If this fails (exit status != 0), return `nil` (not a git repo).
   - Otherwise, store the result as `repoRoot`.

3. Run `git branch --show-current`:
   - If the result is non-empty, use it as `branchName`.
   - If empty (detached HEAD), fall back to step 4.

4. Run `git rev-parse --short HEAD`:
   - Use the short SHA as `branchName`.
   - If this also fails, use the literal string `"HEAD"`.

5. Run `git config --get remote.origin.url`:
   - Store as `remoteURL` (may be `nil` if no remote is configured).

### Process Execution

`private static func run(_ arguments: String..., in directory: URL) -> String?`

| Setting | Value |
|---------|-------|
| Executable | `/usr/bin/git` |
| Arguments | Passed through |
| Working directory | `directory` parameter |
| stdout | Captured via `Pipe` |
| stderr | Redirected to `FileHandle.nullDevice` |

Returns trimmed stdout if exit status is 0, otherwise `nil`.

## Integration Points

### ContentView

- `@State private var gitInfo: GitInfo?`
- `refreshGitInfo()` launches a `Task` calling `GitInfo.fetch(for:)`, updates `gitInfo` on `MainActor`.
- Called in:
  - `.onAppear` (initial load)
  - `.onChange(of: sidebarFileURL)` (file switch)

### PathBarView

- Displays `gitInfo.branchName` at the right end of the path bar.
- Shows `gitInfo.remoteURL` as a hover tooltip.

## Error Handling

- If `git` is not installed: `Process.run()` throws, caught and returns `nil`.
- If not in a git repo: `rev-parse --show-toplevel` returns non-zero, `fetch` returns `nil`.
- If no remote: `remoteURL` is `nil`, tooltip shows "No remote configured".

## Threading

`fetch(for:)` is `async` but not `@MainActor`. The blocking `Process.waitUntilExit()` calls run on the Swift concurrency cooperative thread pool, not the main thread. Results are dispatched to `MainActor` by the caller.
