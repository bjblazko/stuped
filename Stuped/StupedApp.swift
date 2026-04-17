import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Return true so cold launches create a blank editor window
        // instead of showing the open/recent dialog.
        // File-open requests from Finder are handled by DocumentGroup directly.
        true
    }
}

@main
struct StupedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage("editor.wordWrap") private var wordWrap: Bool = false
    @AppStorage("editor.showMiniMap") private var showMiniMap: Bool = true
    @AppStorage("fileTree.showHiddenFiles") private var showHiddenFiles: Bool = false

    var body: some Scene {
        // Single file editing (Finder double-click, File > Open)
        DocumentGroup(newDocument: StupedDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Stuped") {
                    openWindow(id: "about")
                }
            }
            CommandGroup(after: .newItem) {
                Button("Open Folder...") {
                    openFolder()
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
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
        }

        // About
        Window("About Stuped", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Folder browsing
        Window("Stuped — Folder", id: "folder-browser") {
            FolderBrowserView()
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Recent Files") {
                    NotificationCenter.default.post(name: .stupedToggleRecentFiles, object: nil)
                }
                .keyboardShortcut("r")

                Button("Search Files...") {
                    NotificationCenter.default.post(name: .stupedToggleGlobalSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
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
            FolderBrowserState.shared.openFolder(url: url)
            openWindow(id: "folder-browser")
        }
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
        self.folderURL  = url
        self.treeRootURL = url   // reset to project root on fresh open
        self.selectedFileURL = nil
    }
}
