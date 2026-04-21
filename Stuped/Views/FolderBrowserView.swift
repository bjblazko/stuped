import SwiftUI

/// Thin wrapper for the folder-browsing Window scene.
/// Owns the TabManager and routes file selection through it.
struct FolderBrowserView: View {
    @State private var tabManager = TabManager()
    @State private var recentFoldersStore = RecentFoldersStore.shared
    private var folderState = FolderBrowserState.shared

    @State private var showRecentItems = false
    @State private var recentItemsInitialIndex = 0
    @State private var recentItemsCycleTrigger = 0


    private var windowTitle: String {
        if let activeTab = tabManager.activeTab {
            return activeTab.displayName
        }
        if let selected = folderState.selectedFileURL {
            return selected.lastPathComponent
        }
        return folderState.folderURL?.lastPathComponent ?? "Folder"
    }

    /// Binding whose get/set route through the active tab so ContentView always
    /// reads and writes the right tab's content.
    private var activeDocumentBinding: Binding<StupedDocument> {
        Binding(
            get: {
                var doc = StupedDocument()
                doc.text = tabManager.activeTab?.text ?? ""
                return doc
            },
            set: { newDoc in
                guard let tab = tabManager.activeTab else { return }
                // Only mark dirty if text actually changed
                if tab.text != newDoc.text {
                    tab.text = newDoc.text
                }
            }
        )
    }

    var body: some View {
        ZStack {
            ContentView(
                document: activeDocumentBinding,
                fileURL: nil,
                folderMode: true,
                tabManager: tabManager,
                projectRootURL: folderState.folderURL,
                onFileSelected: handleFileSelected,
                onFileSaved: handleFileSaved
            )
            .onReceive(NotificationCenter.default.publisher(for: .stupedToggleRecentItems)) { _ in
                handleRecentItemsCommand()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stupedToggleGlobalSearch)) { _ in
                // Prefer the currently displayed tree root; fall back to the project root.
                let searchRoot = FolderBrowserState.shared.treeRootURL
                                 ?? FolderBrowserState.shared.folderURL
                if let rootURL = searchRoot {
                    GlobalSearchWindowManager.shared.toggle(
                        rootURL: rootURL,
                        onSelect: handleFileSelected
                    )
                }
            }

            if showRecentItems {
                RecentItemsPopupView(
                    tabManager: tabManager,
                    recentFoldersStore: recentFoldersStore,
                    isShowing: $showRecentItems,
                    initialSelectedIndex: recentItemsInitialIndex,
                    cycleTrigger: recentItemsCycleTrigger,
                    onSelectFile: handleFileSelected,
                    onSelectFolder: handleFolderSelected
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

        }
        .animation(.easeOut(duration: 0.12), value: showRecentItems)
        .navigationTitle(windowTitle)
        .onChange(of: folderState.folderURL) { _, newURL in
            GlobalSearchWindowManager.shared.close()
            if let url = newURL {
                tabManager.clearAll()
                loadFolder(url: url)
            }
        }
        .onAppear {
            if let url = folderState.folderURL {
                loadFolder(url: url)
            }
        }
    }

    private func handleRecentItemsCommand() {
        if showRecentItems {
            recentItemsCycleTrigger += 1
        } else {
            recentItemsInitialIndex = tabManager.historyURLsByRecency.count > 1 ? 1 : 0
            recentItemsCycleTrigger = 0
            showRecentItems = true
        }
    }

    private func handleFileSelected(_ url: URL) {
        tabManager.open(url: url)
        FolderBrowserState.shared.selectedFileURL = url
    }

    private func handleFolderSelected(_ url: URL) {
        FolderBrowserState.shared.openFolder(url: url)
    }

    private func handleFileSaved(_ url: URL) {
        tabManager.tabs.first(where: { $0.fileURL == url })?.markSaved()
    }

    private func loadFolder(url: URL) {
        NotificationCenter.default.post(
            name: .stupedFolderOpened,
            object: nil,
            userInfo: ["url": url]
        )
    }
}

extension Notification.Name {
    static let stupedFolderOpened = Notification.Name("stupedFolderOpened")
    static let stupedToggleRecentItems = Notification.Name("stupedToggleRecentItems")
    static let stupedToggleGlobalSearch = Notification.Name("stupedToggleGlobalSearch")
    static let stupedRevealInFileTree = Notification.Name("stupedRevealInFileTree")
    static let stupedCreateNewFile = Notification.Name("stupedCreateNewFile")
    static let stupedCreateNewFolder = Notification.Name("stupedCreateNewFolder")
    static let stupedSetViewMode = Notification.Name("stupedSetViewMode")
}
