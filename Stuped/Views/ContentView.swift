import SwiftUI

struct ContentView: View {
    @Binding var document: StupedDocument
    var fileURL: URL?

    @State private var viewMode: DocumentViewMode = .edit
    @State private var treeModel = FileTreeModel()
    @State private var sidebarFileURL: URL?
    @State private var columnVisibility: NavigationSplitViewVisibility
    @AppStorage("editor.wordWrap") private var wordWrap: Bool = false
    @AppStorage("editor.showMiniMap") private var showMiniMap: Bool = true
    @AppStorage("fileTree.showHiddenFiles") private var showHiddenFiles: Bool = false
    @AppStorage("app.appearance") private var appearanceRaw: String = AppearancePreference.system.rawValue
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
    /// The originally opened folder used as the base for relative path copy actions.
    private let projectRootURL: URL?

    /// Single-file mode: opened via Finder / File > Open. Sidebar hidden by default.
    init(document: Binding<StupedDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
        self.isFolderMode = false
        self.tabManager = nil
        self.onFileSelected = nil
        self.onFileSaved = nil
        self.projectRootURL = nil
        self._columnVisibility = State(initialValue: .detailOnly)
    }

    /// Folder mode with tab support. The tab bar is rendered inside the detail pane;
    /// sidebar clicks are routed through onFileSelected so FolderBrowserView can manage tabs.
    init(document: Binding<StupedDocument>, fileURL: URL?, folderMode: Bool,
         tabManager: TabManager? = nil,
         projectRootURL: URL? = nil,
         onFileSelected: ((URL) -> Void)? = nil,
         onFileSaved: ((URL) -> Void)? = nil) {
        self._document = document
        self.fileURL = fileURL
        self.isFolderMode = folderMode
        self.tabManager = tabManager
        self.projectRootURL = projectRootURL
        self.onFileSelected = onFileSelected
        self.onFileSaved = onFileSaved
        self._columnVisibility = State(initialValue: .all)
    }

    private var activeFileURL: URL? {
        if isFolderMode {
            return sidebarFileURL ?? tabManager?.activeTab?.fileURL
        }
        return fileURL
    }

    private var activeTab: TabItem? {
        tabManager?.activeTab
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

    private var activeViewMode: DocumentViewMode {
        if isImageFile {
            return .preview
        }

        if isFolderMode {
            if let mode = activeTab?.viewMode {
                return mode
            }
            if let activeFileURL {
                return defaultViewMode(for: activeFileURL)
            }
        }

        return viewMode
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            if let tabManager, !tabManager.tabs.isEmpty {
                TabBarView(tabManager: tabManager, projectRootURL: projectRootURL)
            }

            if isFolderMode && activeFileURL == nil {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc.text",
                    description: Text("Select a file from the sidebar to view or edit it.")
                )
            } else {
                detailPanes
            }
        }
    }

    var body: some View {
        Group {
            if isFolderMode {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    FileTreeSidebar(
                        model: treeModel,
                        selectedFileURL: sidebarBinding,
                        projectRootURL: projectRootURL
                    )
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
                } detail: {
                    detailContent
                        .padding(.leading, 2)
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
            if !isFolderMode, isImageFile {
                viewMode = .preview
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stupedFolderOpened)) { notification in
            if isFolderMode, let url = notification.userInfo?["url"] as? URL {
                treeModel.loadDirectory(at: url)
                sidebarFileURL = nil
            }
        }
        .onChange(of: treeModel.rootURL) { _, newURL in
            if isFolderMode {
                FolderBrowserState.shared.treeRootURL = newURL
            }
        }
        .onChange(of: showHiddenFiles, initial: true) { _, newValue in
            treeModel.showHiddenFiles = newValue
            treeModel.rebuildTree()
        }
        .onChange(of: sidebarFileURL) { _, newURL in
            if isFolderMode {
                if let onFileSelected {
                    if let newURL {
                        onFileSelected(newURL)
                    }
                } else {
                    loadFileFromSidebar(url: newURL)
                }
                FolderBrowserState.shared.selectedFileURL = newURL
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stupedTabSwitched)) { notification in
            guard isFolderMode, let url = notification.userInfo?["url"] as? URL else { return }
            sidebarFileURL = url
        }
        .onReceive(NotificationCenter.default.publisher(for: .stupedRevealInFileTree)) { notification in
            guard isFolderMode else { return }
            let url = (notification.userInfo?["url"] as? URL) ?? tabManager?.activeTab?.fileURL
            guard let url else { return }
            treeModel.expandToURL(url)
            sidebarFileURL = url
            columnVisibility = .all
        }
        .onReceive(NotificationCenter.default.publisher(for: .stupedSetViewMode)) { notification in
            guard isPreviewable,
                  let rawValue = notification.userInfo?["mode"] as? String,
                  let mode = DocumentViewMode(rawValue: rawValue) else { return }
            setViewMode(mode)
        }
    }

    private var sidebarBinding: Binding<URL?> {
        Binding(
            get: { sidebarFileURL },
            set: { sidebarFileURL = $0 }
        )
    }

    @ViewBuilder
    private var detailPanes: some View {
        if isFolderMode, let tabManager {
            ZStack {
                ForEach(tabManager.tabs) { tab in
                    let isActive = tab.id == tabManager.activeTabID
                    DocumentPaneView(
                        text: binding(for: tab),
                        fileURL: tab.fileURL,
                        projectRootURL: projectRootURL,
                        viewMode: viewModeBinding(for: tab),
                        wordWrap: wordWrap,
                        showMiniMap: showMiniMap,
                        isActive: isActive,
                        onNavigate: navigateToPath
                    )
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
                    .zIndex(isActive ? 1 : 0)
                }
            }
        } else {
            DocumentPaneView(
                text: $document.text,
                fileURL: fileURL,
                projectRootURL: projectRootURL,
                viewMode: $viewMode,
                wordWrap: wordWrap,
                showMiniMap: showMiniMap,
                isActive: true,
                onNavigate: navigateToPath
            )
        }
    }

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

            Menu {
                if isPreviewable && !isImageFile {
                    Section("View Mode") {
                        Button { setViewMode(.edit) } label: {
                            if activeViewMode == .edit { Label("Edit", systemImage: "checkmark") }
                            else { Text("Edit") }
                        }
                        Button { setViewMode(.split) } label: {
                            if activeViewMode == .split { Label("Split", systemImage: "checkmark") }
                            else { Text("Split") }
                        }
                        Button { setViewMode(.preview) } label: {
                            if activeViewMode == .preview { Label("Preview", systemImage: "checkmark") }
                            else { Text("Preview") }
                        }
                    }
                }
                Section("View") {
                    Button { wordWrap.toggle() } label: {
                        if wordWrap { Label("Word Wrap", systemImage: "checkmark") }
                        else { Text("Word Wrap") }
                    }
                    Button { showMiniMap.toggle() } label: {
                        if showMiniMap { Label("Mini-Map", systemImage: "checkmark") }
                        else { Text("Mini-Map") }
                    }
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.label).tag(preference.rawValue)
                        }
                    }
                }
                Section("File Tree") {
                    Button { showHiddenFiles.toggle() } label: {
                        if showHiddenFiles { Label("Show Dot Files", systemImage: "checkmark") }
                        else { Text("Show Dot Files") }
                    }
                    if isFolderMode {
                        Button("Reveal in File Tree") {
                            guard let url = tabManager?.activeTab?.fileURL else { return }
                            treeModel.expandToURL(url)
                            sidebarFileURL = url
                            columnVisibility = .all
                        }
                        .disabled(tabManager?.activeTab == nil)
                    }
                }
                if isFolderMode {
                    Section("Navigate") {
                        Button("Recent Files & Folders") {
                            NotificationCenter.default.post(name: .stupedToggleRecentItems, object: nil)
                        }
                        Button("Search Files...") {
                            NotificationCenter.default.post(name: .stupedToggleGlobalSearch, object: nil)
                        }
                    }
                }
            } label: {
                Label("View Options", systemImage: "slider.horizontal.3")
            }
            .help("View & Navigation Options")
        }
    }

    private func setupFileTree() {
        if isFolderMode { return }

        guard let fileURL else { return }
        let parentDirectory = fileURL.deletingLastPathComponent()
        treeModel.loadDirectory(at: parentDirectory)
        sidebarFileURL = fileURL
    }

    func loadFolder(at url: URL) {
        treeModel.loadDirectory(at: url)
        sidebarFileURL = nil
    }

    private func loadFileFromSidebar(url: URL?) {
        guard let url else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return }

        if LanguageMap.isImage(url.pathExtension) {
            document.text = ""
            viewMode = .preview
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let checkLength = min(data.count, 8192)
            if data.prefix(checkLength).contains(0x00) {
                document.text = "[Binary file - cannot display]"
                return
            }
            document.text = String(decoding: data, as: UTF8.self)
            viewMode = defaultViewMode(for: url)
        } catch {
            document.text = "Error loading file: \(error.localizedDescription)"
        }
    }

    private func navigateToPath(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if !isFolderMode {
            let folderURL = isDirectory.boolValue ? url : url.deletingLastPathComponent()
            FolderBrowserState.shared.openFolder(url: folderURL)
            openWindow(
                id: AppWindowID.folderBrowser,
                value: AppWindowValue.folderBrowserSingleton
            )
            return
        }

        if isDirectory.boolValue {
            treeModel.loadDirectory(at: url)
            sidebarFileURL = nil
            columnVisibility = .all
        } else {
            let parentDirectory = url.deletingLastPathComponent()
            treeModel.loadDirectory(at: parentDirectory)
            sidebarFileURL = url
            columnVisibility = .all
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
            openWindow(
                id: AppWindowID.folderBrowser,
                value: AppWindowValue.folderBrowserSingleton
            )
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

    private func setViewMode(_ mode: DocumentViewMode) {
        let resolvedMode: DocumentViewMode
        if isImageFile {
            resolvedMode = .preview
        } else if isPreviewable {
            resolvedMode = mode
        } else {
            resolvedMode = .edit
        }

        if isFolderMode, let activeTab {
            activeTab.viewMode = resolvedMode
        } else {
            viewMode = resolvedMode
        }
    }

    private func defaultViewMode(for url: URL) -> DocumentViewMode {
        DocumentViewMode.initialMode(for: url)
    }

    private func binding(for tab: TabItem) -> Binding<String> {
        Binding(
            get: { tab.text },
            set: { tab.text = $0 }
        )
    }

    private func viewModeBinding(for tab: TabItem) -> Binding<DocumentViewMode> {
        Binding(
            get: { tab.viewMode },
            set: { tab.viewMode = $0 }
        )
    }
}
