import SwiftUI

struct ContentView: View {
    @Binding var document: StupedDocument
    var fileURL: URL?

    @State private var viewMode: ViewMode = .edit
    @State private var editorState = EditorState()
    @State private var treeModel = FileTreeModel()
    @State private var sidebarFileURL: URL?
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var gitInfo: GitInfo?
    @State private var findBarHeight: CGFloat = 0
    @AppStorage("editor.wordWrap") private var wordWrap: Bool = false
    @AppStorage("editor.showMiniMap") private var showMiniMap: Bool = true
    @AppStorage("fileTree.showHiddenFiles") private var showHiddenFiles: Bool = false
    @Environment(\.openWindow) private var openWindow

    /// When true, selecting a file in the sidebar loads it into the editor
    /// (replacing the current document text). When false (DocumentGroup mode),
    /// sidebar clicks open new windows.
    private let isFolderMode: Bool
    /// When provided, the tab bar is rendered inside the detail pane and tab management
    /// is delegated to FolderBrowserView instead of ContentView loading files itself.
    private let tabManager: TabManager?
    /// Called when the user selects a file in the sidebar (folder mode with tabs).
    private let onFileSelected: ((URL) -> Void)?
    /// Called after ContentView successfully saves a file, so the caller can clear the dirty flag.
    private let onFileSaved: ((URL) -> Void)?

    enum ViewMode: String, CaseIterable {
        case edit = "Edit"
        case preview = "Preview"
        case split = "Split"
    }

    /// Single-file mode: opened via Finder / File > Open. Sidebar hidden by default.
    init(document: Binding<StupedDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
        self.isFolderMode = false
        self.tabManager = nil
        self.onFileSelected = nil
        self.onFileSaved = nil
        self._columnVisibility = State(initialValue: .detailOnly)
    }

    /// Folder mode with tab support. The tab bar is rendered inside the detail pane;
    /// sidebar clicks are routed through onFileSelected so FolderBrowserView can manage tabs.
    init(document: Binding<StupedDocument>, fileURL: URL?, folderMode: Bool,
         tabManager: TabManager? = nil,
         onFileSelected: ((URL) -> Void)? = nil,
         onFileSaved: ((URL) -> Void)? = nil) {
        self._document = document
        self.fileURL = fileURL
        self.isFolderMode = folderMode
        self.tabManager = tabManager
        self.onFileSelected = onFileSelected
        self.onFileSaved = onFileSaved
        self._columnVisibility = State(initialValue: .all)
    }

    private var activeFileURL: URL? {
        if isFolderMode {
            // Prefer sidebar selection; fall back to active tab so navigating
            // to a folder via breadcrumbs doesn't blank the editor.
            return sidebarFileURL ?? tabManager?.activeTab?.fileURL
        }
        return fileURL
    }

    private var previewType: PreviewType? {
        guard let url = activeFileURL else { return nil }
        return LanguageMap.previewType(for: url.pathExtension)
    }

    private var isPreviewable: Bool {
        previewType != nil
    }

    private var isImageFile: Bool {
        previewType == .image
    }

    private var detectedLanguage: String? {
        guard let url = activeFileURL else { return nil }
        return LanguageMap.language(for: url.pathExtension)
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            if let tm = tabManager, !tm.tabs.isEmpty {
                TabBarView(tabManager: tm)
            }
            if isFolderMode && activeFileURL == nil {
                ContentUnavailableView("No File Selected",
                    systemImage: "doc.text",
                    description: Text("Select a file from the sidebar to view or edit it."))
            } else {
                PathBarView(fileURL: activeFileURL, gitInfo: gitInfo) { url in
                    navigateToPath(url)
                }

                editorArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if isPreviewable && !isImageFile {
                            viewModeOverlay
                                .padding(.top, viewMode == .edit ? findBarHeight : 0)
                                .padding(.trailing, showMiniMap && viewMode == .edit ? MiniMapView.width : 0)
                        }
                    }

                if viewMode != .preview && !isImageFile {
                    StatusBarView(editorState: editorState, language: detectedLanguage)
                }
            }
        }
    }

    var body: some View {
        Group {
            if isFolderMode {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    FileTreeSidebar(rootNode: treeModel.rootNode, selectedFileURL: sidebarBinding)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
                } detail: {
                    detailContent
                }
                .background {
                    Button("") { saveCurrentFile() }
                        .keyboardShortcut("s")
                        .frame(width: 0, height: 0)
                        .opacity(0)
                }
            } else {
                detailContent
            }
        }
        .toolbar {
            toolbarContent
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            setupFileTree()
            if isImageFile {
                viewMode = .preview
            }
            if !isFolderMode {
                editorState.detectLineEnding(in: document.text)
                editorState.detectIndentation(in: document.text)
            }
            refreshGitInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stupedFolderOpened)) { notif in
            if isFolderMode, let url = notif.userInfo?["url"] as? URL {
                treeModel.loadDirectory(at: url)
                sidebarFileURL = nil
            }
        }
        .onChange(of: treeModel.rootURL) { _, newURL in
            // Keep FolderBrowserState in sync so global search always uses the
            // currently displayed tree root, not the stale top-level project folder.
            if isFolderMode { FolderBrowserState.shared.treeRootURL = newURL }
        }
        .onChange(of: viewMode) { _, _ in findBarHeight = 0 }
        .onChange(of: showHiddenFiles, initial: true) { _, newValue in
            treeModel.showHiddenFiles = newValue
            treeModel.rebuildTree()
        }
        .onChange(of: sidebarFileURL) { _, newURL in
            if isFolderMode {
                if let callback = onFileSelected {
                    // Tab-aware mode: caller handles file loading via TabManager.
                    if let url = newURL { callback(url) }
                } else {
                    loadFileFromSidebar(url: newURL)
                }
                FolderBrowserState.shared.selectedFileURL = newURL
            }
            refreshGitInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stupedTabSwitched)) { notif in
            guard isFolderMode, let url = notif.userInfo?["url"] as? URL else { return }
            // Update sidebar highlight and view mode without reloading from disk.
            sidebarFileURL = url
            if LanguageMap.isImage(url.pathExtension) {
                viewMode = .preview
            } else {
                viewMode = .edit
            }
        }
    }

    private var sidebarBinding: Binding<URL?> {
        Binding(
            get: { sidebarFileURL },
            set: { sidebarFileURL = $0 }
        )
    }

    // MARK: - Editor Area

    @ViewBuilder
    private var editorArea: some View {
        switch viewMode {
        case .edit:
            CodeEditorView(text: $document.text, language: detectedLanguage, editorState: editorState, wordWrap: wordWrap, showMiniMap: showMiniMap,
                           onFindBarHeightChanged: { findBarHeight = $0 })
        case .preview:
            previewView
        case .split:
            HSplitView {
                CodeEditorView(text: $document.text, language: detectedLanguage, editorState: editorState, wordWrap: wordWrap, showMiniMap: showMiniMap)
                    .frame(minWidth: 250)
                previewView
                    .frame(minWidth: 250)
            }
        }
    }

    @ViewBuilder
    private var previewView: some View {
        if let pt = previewType {
            switch pt {
            case .markdown, .html:
                MarkdownPreviewView(text: document.text, previewType: pt, fileURL: activeFileURL)
            case .image:
                if let url = activeFileURL {
                    ImagePreviewView(fileURL: url)
                }
            }
        } else {
            Text("Preview not available for this file type.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - View mode overlay

    private var viewModeOverlay: some View {
        HStack(spacing: 1) {
            viewModeButton(.edit,    icon: "doc.plaintext", tooltip: "Edit")
            viewModeButton(.split,   icon: "rectangle.split.2x1", tooltip: "Split")
            viewModeButton(.preview, icon: "eye",           tooltip: "Preview")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
        .padding(10)
    }

    private func viewModeButton(_ mode: ViewMode, icon: String, tooltip: String) -> some View {
        Button { viewMode = mode } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 22)
                .foregroundStyle(viewMode == mode ? .primary : .tertiary)
                .background(
                    viewMode == mode
                        ? RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor))
                        : nil
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button(action: openFileAction) {
                Label("Open File", systemImage: "doc")
            }
            .help("Open File (Cmd+O)")

            Button(action: openFolderAction) {
                Label("Open Folder", systemImage: "folder")
            }
            .help("Open Folder (Cmd+Shift+O)")

            Button(action: saveAction) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .help("Save (Cmd+S)")
            .disabled(isFolderMode && sidebarFileURL == nil)
        }


    }

    // MARK: - File Tree

    private func setupFileTree() {
        if isFolderMode { return } // folder mode sets tree externally

        // Single-file mode: show parent directory
        guard let url = fileURL else { return }
        let parentDir = url.deletingLastPathComponent()
        treeModel.loadDirectory(at: parentDir)
        sidebarFileURL = url
    }

    func loadFolder(at url: URL) {
        treeModel.loadDirectory(at: url)
        sidebarFileURL = nil
    }

    // MARK: - File Operations

    private func loadFileFromSidebar(url: URL?) {
        guard let url = url else { return }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              !isDir.boolValue else { return }

        // Image files: skip text loading, show preview directly
        if LanguageMap.isImage(url.pathExtension) {
            document.text = ""
            viewMode = .preview
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let checkLength = min(data.count, 8192)
            if data.prefix(checkLength).contains(0x00) {
                document.text = "[Binary file — cannot display]"
                return
            }
            document.text = String(decoding: data, as: UTF8.self)
            editorState.detectLineEnding(in: document.text)
            editorState.detectIndentation(in: document.text)
            viewMode = isPreviewable ? .split : .edit
        } catch {
            document.text = "Error loading file: \(error.localizedDescription)"
        }
    }

    private func navigateToPath(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }

        if !isFolderMode {
            // Single-file mode: open folder browser window
            let folderURL = isDir.boolValue ? url : url.deletingLastPathComponent()
            FolderBrowserState.shared.openFolder(url: folderURL)
            openWindow(id: "folder-browser")
            return
        }

        if isDir.boolValue {
            treeModel.loadDirectory(at: url)
            sidebarFileURL = nil
            columnVisibility = .all
        } else {
            // It's a file — load its parent directory and select the file
            let parentDir = url.deletingLastPathComponent()
            treeModel.loadDirectory(at: parentDir)
            sidebarFileURL = url
            columnVisibility = .all
        }
    }

    private func refreshGitInfo() {
        guard let url = activeFileURL else {
            gitInfo = nil
            return
        }
        Task {
            let info = await GitInfo.fetch(for: url)
            await MainActor.run {
                gitInfo = info
            }
        }
    }

    private func openFileAction() {
        NSDocumentController.shared.openDocument(nil)
    }

    private func openFolderAction() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open in Stuped"

        if panel.runModal() == .OK, let url = panel.url {
            FolderBrowserState.shared.openFolder(url: url)
            openWindow(id: "folder-browser")
        }
    }

    private func saveAction() {
        if isFolderMode {
            saveCurrentFile()
        } else {
            NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
        }
    }

    private func saveCurrentFile() {
        guard let url = sidebarFileURL else { return }
        guard !LanguageMap.isImage(url.pathExtension) else { return }
        do {
            try document.text.write(to: url, atomically: true, encoding: .utf8)
            onFileSaved?(url)
        } catch {
            print("Save error: \(error.localizedDescription)")
        }
    }
}
