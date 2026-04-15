import SwiftUI

/// Thin wrapper for the folder-browsing Window scene.
/// Owns the TabManager and routes file selection through it.
struct FolderBrowserView: View {
    @State private var tabManager = TabManager()
    private var folderState = FolderBrowserState.shared

    @State private var showRecentFiles = false
    @State private var recentFilesInitialIndex = 0
    @State private var recentFilesCycleTrigger = 0

    @State private var showGlobalSearch = false

    private var windowTitle: String {
        if let selected = folderState.selectedFileURL {
            return selected.deletingLastPathComponent().lastPathComponent
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
                onFileSelected: handleFileSelected,
                onFileSaved: handleFileSaved
            )
            .onReceive(NotificationCenter.default.publisher(for: .stupedToggleRecentFiles)) { _ in
                handleCmdE()
            }
            .onReceive(NotificationCenter.default.publisher(for: .stupedToggleGlobalSearch)) { _ in
                showGlobalSearch.toggle()
            }

            if showRecentFiles {
                RecentFilesPopupView(
                    tabManager: tabManager,
                    isShowing: $showRecentFiles,
                    initialSelectedIndex: recentFilesInitialIndex,
                    cycleTrigger: recentFilesCycleTrigger,
                    onSelect: handleFileSelected
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if showGlobalSearch, let rootURL = FolderBrowserState.shared.folderURL {
                GlobalSearchPopupView(
                    rootURL: rootURL,
                    isShowing: $showGlobalSearch,
                    onSelect: handleFileSelected
                )
                .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: showRecentFiles)
        .animation(.easeOut(duration: 0.12), value: showGlobalSearch)
        .navigationTitle(windowTitle)
        .onChange(of: folderState.folderURL) { _, newURL in
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

    private func handleCmdE() {
        if showRecentFiles {
            recentFilesCycleTrigger += 1
        } else {
            recentFilesInitialIndex = tabManager.recentTabIDs.count > 1 ? 1 : 0
            recentFilesCycleTrigger = 0
            showRecentFiles = true
        }
    }

    private func handleFileSelected(_ url: URL) {
        tabManager.open(url: url)
        FolderBrowserState.shared.selectedFileURL = url
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
    static let stupedToggleRecentFiles = Notification.Name("stupedToggleRecentFiles")
    static let stupedToggleGlobalSearch = Notification.Name("stupedToggleGlobalSearch")
}
