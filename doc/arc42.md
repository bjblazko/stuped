# Stuped -- Architecture Documentation (arc42)

## 1. Introduction and Goals

### Requirements Overview

Stuped is a native macOS code editor and file browser providing:

- Text editing with syntax highlighting for 100+ languages
- Live Markdown and HTML preview with Mermaid diagram support
- File tree sidebar with real-time directory watching
- In-window tab management for folder mode
- Mini-map overview panel with syntax-colour bars, selection overlay, and click-to-scroll
- Word wrap toggle (hard line breaks vs. unbounded horizontal scroll)
- Recent-files command palette (Cmd+R) showing open tabs and macOS file history
- Git branch and remote origin display
- Path bar with clickable breadcrumb navigation
- "Reveal in File Tree" (Cmd+Shift+J) to expand and highlight the active file in the sidebar
- View Options toolbar menu consolidating all view toggles and navigation shortcuts

### Quality Goals

| Priority | Goal | Measure |
|----------|------|---------|
| 1 | Responsiveness | Typing input latency < 16ms; highlighting/preview debounced |
| 2 | Correctness | Accurate syntax highlighting, faithful Markdown rendering |
| 3 | Simplicity | Minimal dependencies, small codebase (~2000 lines) |

### Stakeholders

| Role | Expectation |
|------|-------------|
| Developer (user) | Fast, lightweight code viewer with preview |
| Maintainer | Small, understandable codebase |

## 2. Constraints

### Technical Constraints

| Constraint | Rationale |
|------------|-----------|
| macOS 15+ | Native SwiftUI full-screen window behavior requires macOS 15; builds use Xcode 26.4 for the latest macOS SDK while preserving macOS 15 deployment |
| Swift 5.9 | Required by HighlighterSwift and Observation framework |
| No App Sandbox | Git subprocess execution and arbitrary file access |
| No network access | All resources bundled; no telemetry or updates |

### Organizational Constraints

| Constraint | Rationale |
|------------|-----------|
| Single developer | Architecture optimized for simplicity over team scaling |
| No Mac App Store | Sandbox requirement incompatible with design |

## 3. Context and Scope

### Business Context

```mermaid
graph LR
    User["User (dev)"] -->|opens / edits| Stuped
    Stuped --> FS["File System\n(read/write)"]
    Stuped --> Git["/usr/bin/git\n(branch info)"]
    Stuped --> WK["WKWebView\n(preview)"]
```

### Technical Context

| External System | Interface | Purpose |
|-----------------|-----------|---------|
| macOS File System | `FileManager`, `open()` | Read/write files, directory listing, kqueue watching |
| `/usr/bin/git` | `Foundation.Process` | Branch name, remote URL, repo root detection |
| WebKit (in-process) | `WKWebView`, `evaluateJavaScript` | Markdown/HTML rendering |
| highlight.js (JavaScriptCore) | `Highlighter` (HighlighterSwift) | Editor syntax highlighting |

## 4. Solution Strategy

| Goal | Strategy |
|------|----------|
| Native feel | SwiftUI for layout; AppKit NSTextView for editing |
| Rich preview | WKWebView with bundled markdown-it + mermaid.js |
| Responsiveness | Debounced highlighting (150ms) and preview (300ms) |
| File awareness | kqueue-based directory watching via DispatchSource |
| Git context | Shell out to git CLI asynchronously |
| Minimal footprint | One external Swift dependency; JS libs bundled as resources |

## 5. Building Block View

### Level 1: System Context

```mermaid
graph TD
    subgraph StupedApp
        DG["DocumentGroup\n(single file)"]
        WS["Window\n'folder-browser'"]
    end

    DG --> CV["ContentView"]
    WS --> FBV["FolderBrowserView"] --> CV

    CV --> FTS["FileTreeSidebar"]
    CV --> EA["Editor Area"]
    CV --> SBV["StatusBarView"]

    EA --> CEV["CodeEditorView\n(NSTextView + MiniMapView)"]
    EA --> MPV["MarkdownPreviewView\n(WKWebView)"]
```

### Level 2: ContentView Internals

```mermaid
graph TD
    subgraph ContentView
        subgraph State
            viewMode["viewMode: ViewMode"]
            editorState["editorState: EditorState"]
            treeModel["treeModel: FileTreeModel"]
            sidebarFileURL["sidebarFileURL: URL?"]
            gitInfo["gitInfo: GitInfo?"]
        end
        subgraph Binding
            document["document: StupedDocument"]
        end
        subgraph Computed
            activeFileURL["activeFileURL: URL?"]
            previewType["previewType: PreviewType?"]
            detectedLanguage["detectedLanguage: String?"]
        end
    end

    ContentView --> NSV["NavigationSplitView"]
    NSV --> Sidebar["FileTreeSidebar\n(rootNode, selectedFileURL, expandedURLs)"]
    NSV --> Detail["Detail VStack"]
    Detail --> PBV["PathBarView\n(fileURL, gitInfo, onNavigate)"]
    Detail --> EditorArea["editorArea"]
    Detail --> SBV["StatusBarView\n(editorState, language)"]

    EditorArea -->|".edit"| CEV["CodeEditorView"]
    EditorArea -->|".preview"| MPV["MarkdownPreviewView"]
    EditorArea -->|".split"| Split["HSplitView\n(CodeEditor + Preview)"]
```

## 6. Runtime View

### Scenario: User opens a Markdown file and edits it

```mermaid
sequenceDiagram
    actor User
    participant CV as ContentView
    participant CE as CodeEditorView
    participant MP as MarkdownPreviewView

    User->>CV: open file
    CV->>CE: load text
    CV->>CV: set viewMode = .split
    CE->>MP: build HTML
    MP->>MP: load WKWebView

    User->>CE: type character
    CE->>CE: textDidChange()
    CE->>CE: debounce 150ms
    CE->>CE: highlight()
    CE->>CV: update text binding
    CV->>MP: updateNSView
    MP->>MP: debounce 300ms
    MP->>MP: evaluateJS renderMarkdown()
```

### Scenario: User clicks a path component

```mermaid
sequenceDiagram
    actor User
    participant PB as PathBarView
    participant CV as ContentView
    participant FTM as FileTreeModel

    User->>PB: click path component
    PB->>CV: onNavigate(url)
    CV->>CV: navigateToPath(url)
    CV->>FTM: loadDirectory(url)
    CV->>CV: sidebarFileURL = nil
    CV->>CV: columnVisibility = .all
```

## 7. Deployment View

```mermaid
graph TD
    subgraph "Stuped.app"
        subgraph "Contents/MacOS"
            Exec["Stuped (executable)"]
        end
        subgraph "Contents/Resources"
            MD["markdown-it.min.js (124 KB)"]
            HL["highlight.min.js (127 KB)"]
            MM["mermaid.min.js (3.2 MB)"]
            CSS1["preview-styles.css (3.8 KB)"]
            CSS2["hljs-github.css (1.3 KB)"]
            CSS3["hljs-github-dark.css (1.3 KB)"]
            Assets["Assets.xcassets"]
        end
        Plist["Info.plist"]
        subgraph "Contents/Frameworks"
            HSF["Highlighter.framework"]
        end
    end
```

Distribution: direct download or Homebrew (not Mac App Store due to no sandbox).

## 8. Crosscutting Concepts

### Dark/Light Mode

- **Editor**: theme switches between `atom-one-dark` and `atom-one-light` via `NSApp.effectiveAppearance` observation.
- **Preview**: CSS `prefers-color-scheme: dark` media query selects code theme; Mermaid re-initializes on appearance change.
- **UI chrome**: SwiftUI `.bar` and `.secondary` colors adapt automatically.

### Debouncing

Used in two places to avoid excessive computation:

| Component | Delay | Mechanism |
|-----------|-------|-----------|
| Syntax highlighting | 150ms | `DispatchWorkItem` on main queue |
| Preview rendering | 300ms | `DispatchWorkItem` on main queue |

### Binary File Safety

Files are checked for null bytes in the first 8192 bytes before loading. Binary files show a placeholder message and are not editable.

### State Management

- `@Observable` (Observation framework) for models: `EditorState`, `FileTreeModel`, `FolderBrowserState`.
- `@State` and `@Binding` for view-local state.
- `NotificationCenter` for cross-window communication (folder opened notification).

## 9. Architecture Decisions

See [`doc/adr/`](adr/) for detailed Architecture Decision Records:

| ADR | Title |
|-----|-------|
| [0001](adr/0001-swiftui-with-appkit-bridging.md) | SwiftUI with AppKit Bridging |
| [0002](adr/0002-document-based-app-architecture.md) | Document-Based App Architecture |
| [0003](adr/0003-webkit-for-preview-rendering.md) | WebKit for Preview Rendering |
| [0004](adr/0004-highlighterswift-for-syntax-highlighting.md) | HighlighterSwift for Syntax Highlighting |
| [0005](adr/0005-kqueue-file-watching.md) | kqueue for File Watching |
| [0006](adr/0006-no-app-sandbox.md) | No App Sandbox |
| [0007](adr/0007-git-integration-via-process.md) | Git Integration via Process |
| [0008](adr/0008-debounced-rendering.md) | Debounced Rendering |
| [0009](adr/0009-external-script-loading-for-wkwebview.md) | External Script Loading for Large JS in WKWebView |
| [0010](adr/0010-in-window-tab-management.md) | In-Window Tab Management for Folder Mode |
| [0011](adr/0011-view-mode-overlay.md) | View Mode Switcher as In-Editor Overlay |
| [0012](adr/0012-minimap-two-pass-normalization.md) | Mini-Map Two-Pass Width Normalisation |

## 10. Quality Requirements

### Quality Tree

```mermaid
mindmap
  root((Quality))
    Performance
      Typing latency < 16ms
      Highlighting within debounce window
      Preview renders within 500ms
    Usability
      macOS conventions (Cmd+O, Cmd+S, Cmd+F)
      Dark/light mode everywhere
      No configuration required
    Reliability
      Binary files handled gracefully
      Missing git handled gracefully
      Large files degrade gracefully
    Maintainability
      Small codebase (~2000 lines)
      One external Swift dependency
      Standard SwiftUI patterns
```

### Quality Scenarios

| Scenario | Measure |
|----------|---------|
| User types rapidly in a 10,000-line file | Keystrokes are never dropped; highlighting catches up within 150ms of last keystroke |
| User opens a 5 MB binary file | File is detected as binary within 1ms; placeholder shown; no crash |
| User opens a file outside any git repo | Path bar shows path without branch; no error |
| System switches from light to dark mode | Editor re-highlights with dark theme; preview re-renders with dark CSS |

## 11. Risks and Technical Debt

| Risk | Impact | Mitigation |
|------|--------|------------|
| kqueue watches only root directory | Subdirectory changes not reflected | Accept for now; could switch to FSEvents for recursive watching |
| Full re-highlight on every change | Slow for very large files | 1 MB cap; could adopt tree-sitter for incremental parsing |
| Bundled mermaid.min.js is 3.2 MB | Large app bundle | Accept; could lazy-load if bundle size becomes a concern |
| No automated tests | Regressions undetected | Add unit tests for models and UI tests for key flows |
| `Process.waitUntilExit()` blocks thread | Thread pool starvation under heavy load | Acceptable for 3 quick git commands; could use async Process API |

## 12. Glossary

| Term | Definition |
|------|------------|
| DocumentGroup | SwiftUI scene type for document-based apps |
| FileDocument | Protocol for reading/writing file contents |
| NSViewRepresentable | Protocol for wrapping AppKit views in SwiftUI |
| Coordinator | Object mediating between SwiftUI and AppKit delegates |
| kqueue | macOS kernel event notification mechanism |
| DispatchSource | GCD wrapper around kqueue for file system monitoring |
| markdown-it | JavaScript library for parsing Markdown to HTML |
| highlight.js | JavaScript library for syntax highlighting |
| Mermaid | JavaScript library for rendering diagrams from text |
| HighlighterSwift | Swift package wrapping highlight.js via JavaScriptCore |
| PreviewType | Enum (`.markdown`, `.html`, `.image`) controlling preview rendering path |
| ViewMode | Enum (`.edit`, `.preview`, `.split`) controlling editor layout |
