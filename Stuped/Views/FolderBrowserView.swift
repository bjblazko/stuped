import SwiftUI

/// Thin wrapper for the folder-browsing WindowGroup scene.
/// Delegates to ContentView in folder mode.
struct FolderBrowserView: View {
    @State private var document = StupedDocument()
    private var folderState = FolderBrowserState.shared

    var body: some View {
        ContentView(document: $document, fileURL: nil, folderMode: true)
            .onChange(of: folderState.folderURL) { _, newURL in
                if let url = newURL {
                    loadFolder(url: url)
                }
                updateWindowTitle(to: newURL)
            }
            .onAppear {
                if let url = folderState.folderURL {
                    loadFolder(url: url)
                }
                updateWindowTitle(to: folderState.folderURL)
            }
    }

    private func updateWindowTitle(to url: URL?) {
        guard let window = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "folder-browser"
        }) else { return }
        window.title = url?.lastPathComponent ?? "Folder"
    }

    // We need a reference to the ContentView to call loadFolder,
    // but since ContentView owns the tree model, we pass via notification
    private func loadFolder(url: URL) {
        // Post notification that ContentView observes
        NotificationCenter.default.post(
            name: .stupedFolderOpened,
            object: nil,
            userInfo: ["url": url]
        )
    }
}

extension Notification.Name {
    static let stupedFolderOpened = Notification.Name("stupedFolderOpened")
}
