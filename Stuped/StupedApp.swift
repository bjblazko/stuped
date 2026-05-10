import SwiftUI
import UniformTypeIdentifiers

enum AppWindowID {
    static let about = "stuped-about-window"
    static let folderBrowser = "stuped-folder-browser-group"
}

enum AppWindowValue {
    static let folderBrowserSingleton = "main"
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var lastShiftTime: Date?
    private var shiftCount = 0

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearancePreference.apply()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { _ in AppearancePreference.apply() }

        installDoubleShiftMonitor()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.newDocument(nil)
            }
        }
    }

    private func installDoubleShiftMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            let isShift = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .shift
            if isShift {
                let now = Date()
                if let last = lastShiftTime, now.timeIntervalSince(last) < 0.3 {
                    shiftCount += 1
                } else {
                    shiftCount = 1
                }
                lastShiftTime = now
                if shiftCount == 2 {
                    NotificationCenter.default.post(name: .stupedToggleFileSearch, object: nil)
                    shiftCount = 0
                }
            }
            return event
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
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
    @State private var folderBrowserState = FolderBrowserState.shared
    @AppStorage("editor.wordWrap") private var wordWrap: Bool = false
    @AppStorage("editor.showMiniMap") private var showMiniMap: Bool = true
    @AppStorage("fileTree.showHiddenFiles") private var showHiddenFiles: Bool = false
    @AppStorage("app.appearance") private var appearanceRaw: String = AppearancePreference.system.rawValue

    init() {
        UserDefaults.standard.register(defaults: ["NSShowOpenPanelOnLaunch": false])
    }

    var body: some Scene {
        DocumentGroup(newDocument: StupedDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .windowFullScreenBehavior(.enabled)
                .onOpenURL { url in
                    if url.hasDirectoryPath {
                        openFolder(url: url)
                    }
                }
        }
        // App commands are installed once here. Registering the same command set on
        // multiple scenes causes macOS to duplicate native menu actions like File > Open.
        .commands {
            allCommands
        }

        WindowGroup("Stuped — Folder", id: AppWindowID.folderBrowser, for: String.self) { _ in
            FolderBrowserView()
                .windowFullScreenBehavior(.enabled)
                .onOpenURL { url in
                    if url.hasDirectoryPath {
                        openFolder(url: url)
                    }
                }
        } defaultValue: {
            AppWindowValue.folderBrowserSingleton
        }
        .defaultSize(width: 900, height: 600)

        Window("About Stuped", id: AppWindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
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
        let normalizedURL = url.standardizedFileURL
        FolderBrowserState.shared.openFolder(url: normalizedURL)
        openWindow(
            id: AppWindowID.folderBrowser,
            value: AppWindowValue.folderBrowserSingleton
        )
    }

    @CommandsBuilder
    private var allCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Stuped") {
                openWindow(id: AppWindowID.about)
            }
        }

        // Add Open Folder to the standard File menu.
        // We let the system handle New/Open/Open Recent for files.
        // Since we added .folder to readableContentTypes, the system Open... 
        // dialog will allow selecting folders, and our onOpenURL/ContentView 
        // logic will handle the redirection.
        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
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

        CommandGroup(after: .sidebar) {
            Button("New File") {
                NotificationCenter.default.post(name: .stupedCreateNewFile, object: nil)
            }
            .disabled(!folderBrowserState.canCreateInSelectedDirectory)
            Button("New Folder") {
                NotificationCenter.default.post(name: .stupedCreateNewFolder, object: nil)
            }
            .disabled(!folderBrowserState.canCreateInSelectedDirectory)
            Divider()
            Button("Recent Files & Folders") {
                NotificationCenter.default.post(name: .stupedToggleRecentItems, object: nil)
            }
            .keyboardShortcut("r")
            Button("Search Files...") {
                NotificationCenter.default.post(name: .stupedToggleGlobalSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Open Quickly...") {
                NotificationCenter.default.post(name: .stupedToggleFileSearch, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command])
            Button("Reveal in File Tree") {
                NotificationCenter.default.post(name: .stupedRevealInFileTree, object: nil)
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Git Changes") {
                NotificationCenter.default.post(name: .stupedShowGitChanges, object: nil)
            }
            .disabled(folderBrowserState.folderURL == nil)
        }
    }
}

@Observable
class FolderBrowserState {
    static let shared = FolderBrowserState()
    var folderURL: URL?
    var selectedFileURL: URL?
    var selectedTreeItemURL: URL?
    var selectedTreeItemIsDirectory = false
    var treeRootURL: URL?
    var canCreateInSelectedDirectory: Bool {
        selectedTreeItemURL != nil && selectedTreeItemIsDirectory
    }
    func updateTreeSelection(url: URL?, isDirectory: Bool) {
        selectedTreeItemURL = url?.standardizedFileURL
        selectedTreeItemIsDirectory = isDirectory
    }
    func openFolder(url: URL) {
        let normalizedURL = url.standardizedFileURL
        RecentFoldersStore.shared.record(normalizedURL)
        self.folderURL = normalizedURL
        self.treeRootURL = normalizedURL
        self.selectedFileURL = nil
        self.selectedTreeItemURL = nil
        self.selectedTreeItemIsDirectory = false
    }
}
