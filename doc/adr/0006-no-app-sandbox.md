# ADR-0006: No App Sandbox

## Status

Accepted

## Context

macOS apps can opt into App Sandbox for security isolation. Sandboxed apps have restricted file system access (only user-granted files) and cannot run arbitrary subprocesses.

Stuped needs to:

1. Open arbitrary files and directories selected by the user.
2. Run `git` commands via `Process` to display branch and remote info.
3. Use `open()` with `O_EVTONLY` for file watching.

## Decision

Disable App Sandbox in the entitlements:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

Hardened Runtime remains enabled for code signing integrity.

## Consequences

### Positive

- Unrestricted file system access for reading, writing, and watching.
- Can execute `/usr/bin/git` without sandbox entitlement exceptions.
- Simpler development with no sandbox-related debugging.

### Negative

- Cannot be distributed via the Mac App Store (sandbox is required).
- Reduced security isolation: a compromised app has full user-level access.
- Must be distributed via direct download, Homebrew, or similar.
- **Critical Requirement:** Because sandboxing is disabled, the app must implement its own security boundaries for untrusted content (e.g., restricting `WKWebView` file access to the project/file scope and using strict security levels for third-party JS libraries).
