import SwiftUI

enum AppWindowID {
    static let about = "about"
    static let folderBrowser = "folder-browser"
}

enum AppWindowValue {
    static let folderBrowserSingleton = "main"
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Returning false suppresses the system open/recents panel that DocumentGroup
        // shows on cold launch in macOS 14+. We create the blank window ourselves
        // in applicationDidFinishLaunching if no file was provided.
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearancePreference.apply()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { _ in AppearancePreference.apply() }

        // Finder-initiated opens arrive via application(_:openFile:) before this
        // point, so documents will already be populated. If the list is empty, this
        // is a cold launch with no file argument — open a blank editor window.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.newDocument(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Clicking the Dock icon when all windows are closed should open a blank editor.
        if !hasVisibleWindows {
            NSDocumentController.shared.newDocument(nil)
        }
        return true
    }
}

@main
struct StupedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var recentFoldersStore = RecentFoldersStore.shared
    @AppStorage("editor.wordWrap") private var wordWrap: Bool = false
    @AppStorage("editor.showMiniMap") private var showMiniMap: Bool = true
    @AppStorage("fileTree.showHiddenFiles") private var showHiddenFiles: Bool = false
    @AppStorage("app.appearance") private var appearanceRaw: String = AppearancePreference.system.rawValue

    var body: some Scene {
        // Single file editing (Finder double-click, File > Open)
        DocumentGroup(newDocument: StupedDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .windowFullScreenBehavior(.enabled)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Stuped") {
                    openWindow(id: AppWindowID.about)
                }
            }
            CommandGroup(after: .newItem) {
                Button("Open Folder...") {
                    openFolder()
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.label).tag(pref.rawValue)
                    }
                }
                Divider()
                Button("Edit Mode") {
                    NotificationCenter.default.post(
                        name: .stupedSetViewMode, object: nil, userInfo: ["mode": "Edit"])
                }
                .keyboardShortcut("1")
                Button("Split View") {
                    NotificationCenter.default.post(
                        name: .stupedSetViewMode, object: nil, userInfo: ["mode": "Split"])
                }
                .keyboardShortcut("2")
                Button("Preview") {
                    NotificationCenter.default.post(
                        name: .stupedSetViewMode, object: nil, userInfo: ["mode": "Preview"])
                }
                .keyboardShortcut("3")
                Divider()
                Button(showMiniMap ? "Disable Mini-Map" : "Enable Mini-Map") {
                    showMiniMap.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Button(wordWrap ? "Disable Word Wrap" : "Enable Word Wrap") {
                    wordWrap.toggle()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                Button(showHiddenFiles ? "Hide Dot Files" : "Show Dot Files") {
                    showHiddenFiles.toggle()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Section {
                    Button("Find...") {
                        Self.performTextFinderAction(.showFindInterface)
                    }
                    .keyboardShortcut("f")

                    Button("Find and Replace...") {
                        Self.performTextFinderAction(.showReplaceInterface)
                    }
                    .keyboardShortcut("f", modifiers: [.command, .option])

                    Button("Find Next") {
                        Self.performTextFinderAction(.nextMatch)
                    }
                    .keyboardShortcut("g")

                    Button("Find Previous") {
                        Self.performTextFinderAction(.previousMatch)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])

                    Button("Use Selection for Find") {
                        Self.performTextFinderAction(.setSearchString)
                    }
                    .keyboardShortcut("e")
                }
            }
            recentFoldersCommands
        }

        // About
        Window("About Stuped", id: AppWindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Folder browsing
        WindowGroup("Stuped — Folder", id: AppWindowID.folderBrowser, for: String.self) { _ in
            FolderBrowserView()
                .windowFullScreenBehavior(.enabled)
        } defaultValue: {
            AppWindowValue.folderBrowserSingleton
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Recent Files & Folders") {
                    NotificationCenter.default.post(name: .stupedToggleRecentItems, object: nil)
                }
                .keyboardShortcut("r")

                Button("Search Files...") {
                    NotificationCenter.default.post(name: .stupedToggleGlobalSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Reveal in File Tree") {
                    NotificationCenter.default.post(name: .stupedRevealInFileTree, object: nil)
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            }
            recentFoldersCommands
        }
    }

    private static func performTextFinderAction(_ action: NSTextFinder.Action) {
        let menuItem = NSMenuItem()
        menuItem.tag = action.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: menuItem)
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open in Stuped"

        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url: url)
        }
    }

    private func openFolder(url: URL) {
        FolderBrowserState.shared.openFolder(url: url)
        openWindow(
            id: AppWindowID.folderBrowser,
            value: AppWindowValue.folderBrowserSingleton
        )
    }

    @CommandsBuilder
    private var recentFoldersCommands: some Commands {
        CommandMenu("Recent Folders") {
            if recentFoldersStore.recentFolders.isEmpty {
                Button("No Recent Folders") {}
                    .disabled(true)
            } else {
                ForEach(recentFoldersStore.recentFolders, id: \.path) { url in
                    Button(recentFolderMenuTitle(for: url)) {
                        openFolder(url: url)
                    }
                }
            }

            Divider()

            Button("Clear Recent Folders") {
                recentFoldersStore.clear()
            }
            .disabled(recentFoldersStore.recentFolders.isEmpty)
        }
    }

    private func recentFolderMenuTitle(for url: URL) -> String {
        let parentPath = abbreviatedPath(for: url.deletingLastPathComponent())
        guard !parentPath.isEmpty, parentPath != "/" else {
            return url.lastPathComponent
        }
        return "\(url.lastPathComponent) — \(parentPath)"
    }

    private func abbreviatedPath(for url: URL) -> String {
        let path = url.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }
}

@Observable
class FolderBrowserState {
    static let shared = FolderBrowserState()
    var folderURL: URL?
    var selectedFileURL: URL?

    /// The URL currently shown as the root of the sidebar tree.
    /// Updated by ContentView whenever treeModel.rootURL changes via breadcrumb navigation.
    /// Always use this (not folderURL) as the search scope.
    var treeRootURL: URL?

    func openFolder(url: URL) {
        let normalizedURL = url.standardizedFileURL
        RecentFoldersStore.shared.record(normalizedURL)
        self.folderURL = normalizedURL
        self.treeRootURL = normalizedURL   // reset to project root on fresh open
        self.selectedFileURL = nil
    }
}
