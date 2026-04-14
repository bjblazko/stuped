# ADR-0001: SwiftUI with AppKit Bridging

## Status

Accepted

## Context

Stuped needs a text editor with features like line numbers, syntax highlighting, cursor tracking, and custom key handling (Tab/Shift+Tab). It also needs a web-based preview pane.

SwiftUI's `TextEditor` is limited: no line numbers, no programmatic control over attributed strings, no delegate callbacks for selection changes. A rich text editing experience requires AppKit's `NSTextView`. Similarly, SwiftUI has no built-in web rendering -- `WKWebView` from WebKit is required.

## Decision

Use SwiftUI as the primary UI framework for layout, navigation, toolbar, and state management. Bridge to AppKit via `NSViewRepresentable` for two components:

1. **CodeEditorView** wraps `NSTextView` + `LineNumberGutterView` + `NSScrollView`.
2. **MarkdownPreviewView** wraps `WKWebView`.

Each uses the Coordinator pattern (`makeCoordinator()`) for delegate callbacks and state synchronization.

## Consequences

### Positive

- SwiftUI handles layout, toolbar, sidebar, state, and reactive updates naturally.
- Full access to NSTextView's rich editing capabilities (attributed strings, layout manager, key events).
- Full access to WKWebView's rendering engine for Markdown/HTML preview.

### Negative

- Two-way binding between SwiftUI `@State`/`@Binding` and NSView requires careful feedback-loop prevention (the `isUpdatingFromTextView` flag pattern).
- View identity management is more complex: SwiftUI may recreate the `NSView` or reuse it across updates, requiring defensive coding in `updateNSView`.
- Debugging crosses framework boundaries, making issues harder to trace.
