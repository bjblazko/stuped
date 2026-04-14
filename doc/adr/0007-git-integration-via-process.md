# ADR-0007: Git Integration via Process

## Status

Accepted

## Context

Stuped displays the current git branch and remote origin URL. Options for accessing git data:

1. **Shell out to `git` CLI** via `Foundation.Process`: simple, uses the user's installed git, supports all git features.
2. **libgit2 (SwiftGit2)**: native library, no subprocess overhead. Adds a large dependency and C interop complexity.
3. **Parse `.git/` files directly**: no dependencies, but fragile and incomplete (doesn't handle worktrees, packed refs, etc.).

## Decision

Shell out to `/usr/bin/git` via `Foundation.Process`. Three commands are run sequentially:

1. `git rev-parse --show-toplevel`
2. `git branch --show-current` (with `rev-parse --short HEAD` fallback)
3. `git config --get remote.origin.url`

Stderr is redirected to `/dev/null`. The method is `async` and runs on a background thread via Swift concurrency.

## Consequences

### Positive

- Zero dependencies beyond the system-installed git.
- Correct behavior for all git configurations (worktrees, bare repos, detached HEAD).
- Simple implementation (~50 lines).
- Easy to extend with additional git queries.

### Negative

- Requires git to be installed (standard on macOS with Xcode/CLT).
- Three sequential subprocess invocations per file change (~10-30ms total).
- `Process.waitUntilExit()` blocks the calling thread (acceptable on a concurrency pool thread).
- No sandbox compatibility (see ADR-0006).
