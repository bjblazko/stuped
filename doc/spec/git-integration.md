# Specification: Git Integration

## Files

- `Stuped/Models/GitCLI.swift`
- `Stuped/Models/GitInfo.swift`
- `Stuped/Models/GitWorkingTreeStatus.swift`
- `Stuped/Views/PathBarView.swift`
- `Stuped/Views/GitChangesWindowManager.swift`
- `Stuped/Views/GitChangesPopupView.swift`

## Overview

Git integration has two layers:

1. **Repository metadata** for the path bar (`GitInfo`) — branch name, remote URL, repo root.
2. **Working-tree status** for folder mode (`GitWorkingTreeStatus`) — repo-scoped lists of new, modified, and deleted files used by the file tree and the Git Changes window.

Both layers shell out to `/usr/bin/git` via `Foundation.Process`.

## GitCLI

`GitCLI` centralizes git process execution and path resolution helpers.

### Responsibilities

- Resolve a working directory from a file or directory URL.
- Resolve the enclosing repository root using `git rev-parse --show-toplevel`.
- Run arbitrary git commands and return either raw stdout or trimmed stdout.

### Process execution

| Setting | Value |
|---------|-------|
| Executable | `/usr/bin/git` |
| Arguments | Passed through |
| Working directory | `directory` parameter |
| stdout | Captured via `Pipe` |
| stderr | Redirected to `FileHandle.nullDevice` |

`run(_:)` returns raw stdout, while `runTrimmed(_:)` trims surrounding whitespace and newlines for metadata lookups such as branch names.

## GitInfo

`GitInfo` remains the lightweight metadata view used by each `DocumentPaneView`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `branchName` | `String` | Current branch name or short SHA |
| `remoteURL` | `String?` | `remote.origin.url` if configured |
| `repoRoot` | `URL` | Absolute repository root |

### Fetch flow

`static func fetch(for fileURL: URL) async -> GitInfo?`

1. Resolve a git working directory via `GitCLI.workingDirectory(for:)`.
2. Resolve the repository root via `GitCLI.repositoryRoot(for:)`; return `nil` when outside git.
3. Read `git branch --show-current`; if detached, fall back to `git rev-parse --short HEAD`.
4. Read `git config --get remote.origin.url`.

## GitWorkingTreeStatus

`GitWorkingTreeStatus` fetches the folder-mode working tree snapshot used by both status-driven UI surfaces.

### Status scope

- Based on `git status --porcelain=v1 --untracked-files=all`
- Includes **untracked/new**, **modified**, and **deleted**
- Excludes ignored files
- Collapses rarer raw git states (`R`, `C`, `T`, `U`) into the UI group **Modified**

### Models

| Type | Purpose |
|------|---------|
| `GitWorkingTreeChangeKind` | UI grouping and decoration metadata for `new`, `modified`, `deleted` |
| `GitChangedFile` | Repo-relative file entry with resolved URL and availability check |
| `GitWorkingTreeStatusSnapshot` | Immutable snapshot for one repo, with grouped lookups and URL-based status lookup |

### Parsing

`GitWorkingTreeStatus.fetch(for:)`:

1. Resolves the repository root via `GitCLI.repositoryRoot(for:)`.
2. Runs `git -c core.quotepath=false status --porcelain=v1 --untracked-files=all`.
3. Parses each status line into a normalized repo-relative path.
4. Classifies the line into `new`, `modified`, or `deleted`.
5. Builds a `GitWorkingTreeStatusSnapshot` keyed by standardized file URLs.

Deleted files remain in the snapshot even though they no longer exist on disk.

## Integration points

### DocumentPaneView + PathBarView

- `DocumentPaneView` still fetches `GitInfo` per active file for branch display.
- `PathBarView` shows the branch badge and tooltip in all modes.
- In **folder mode**, `PathBarView` also receives `onShowGitChanges`, making the branch badge clickable.

### ContentView

Folder mode owns the current `gitStatusSnapshot`.

Refresh triggers:

- `.onAppear`
- `.stupedFolderOpened`
- tree-root changes
- debounced `FileTreeModel.filesystemChangeCount` updates from FSEvents
- debounced `NSApplication.didBecomeActiveNotification` to catch index-only git operations such as `git add`

Active file / sidebar selection changes reuse the existing repo snapshot instead of immediately refetching `git status`, which reduces repo-wide refresh churn while browsing files inside the same tree.

### FileTreeSidebar

- Calls `gitStatusSnapshot.changeKind(for: node.url)` for file rows.
- Uses that change kind for text tinting and overlay icon badges.
- Does **not** synthesize missing deleted rows into the tree; deleted files instead appear in the Git Changes window.

### Git Changes window

- `GitChangesWindowManager` hosts a singleton native `NSPanel`.
- The panel enforces a minimum usable content size and ignores stale autosaved frames that restore below that threshold.
- `GitChangesPopupView` groups entries by **New**, **Modified**, and **Deleted**.
- The panel can be opened from either the clickable git branch badge in the path bar or **View > Git Changes** in folder mode.
- Selecting an available file routes back into folder-mode tab opening (`TabManager.open(url:)` via existing callbacks).

## Error handling

- If `git` is unavailable or the path is outside a repository, git lookups return `nil`.
- If the working tree is clean, the snapshot is still valid but contains `changes == []`.
- Deleted or otherwise unavailable entries remain visible in the Git Changes window and are not opened.

## Threading

Both `GitInfo.fetch(for:)` and `GitWorkingTreeStatus.fetch(for:)` are `async` wrappers around blocking subprocess calls. Callers launch them in `Task`s and publish results back on `MainActor`.

`ContentView` cancels any in-flight working-tree refresh before scheduling the next one and applies a short debounce for file-system and app-reactivation driven refreshes.
