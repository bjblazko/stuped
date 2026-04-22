import Foundation
import Observation
import CoreServices

enum FileTreeCreationKind: String, Equatable {
    case file
    case folder

    var menuTitle: String {
        switch self {
        case .file:
            "New File"
        case .folder:
            "New Folder"
        }
    }

    var systemImageName: String {
        switch self {
        case .file:
            "doc.badge.plus"
        case .folder:
            "folder.badge.plus"
        }
    }

    var placeholder: String {
        switch self {
        case .file:
            "New File"
        case .folder:
            "New Folder"
        }
    }
}

struct PendingFileTreeCreation: Identifiable, Equatable {
    let id = UUID()
    let kind: FileTreeCreationKind
    let parentURL: URL
    var name = ""
    var validationMessage: String?
}

struct FileTreeCreatedItem: Equatable {
    let kind: FileTreeCreationKind
    let url: URL
}

private enum FileTreeCreationError: LocalizedError {
    case noDirectorySelected
    case noPendingCreation
    case emptyName
    case reservedName
    case invalidCharacters
    case alreadyExists(String)
    var errorDescription: String? {
        switch self {
        case .noDirectorySelected:
            "Select a folder first."
        case .noPendingCreation:
            "There is no pending item to create."
        case .emptyName:
            "Enter a name first."
        case .reservedName:
            "'.' and '..' cannot be used as names."
        case .invalidCharacters:
            "Names cannot contain '/' or ':'."
        case .alreadyExists(let name):
            "'\(name)' already exists in this folder."
        }
    }
}

@Observable
class FileTreeModel {
    var rootNode: FileNode?
    var rootURL: URL?
    var showHiddenFiles = false
    var expandedURLs: Set<URL> = []
    var selectedItemURL: URL?
    var pendingCreation: PendingFileTreeCreation?
    var revealTargetURL: URL?
    var revealRequestID = 0
    var filesystemChangeCount = 0

    private var eventStream: FSEventStreamRef?
    private let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .nameKey, .isHiddenKey]

    deinit {
        stopWatching()
    }

    func loadDirectory(at url: URL) {
        self.rootURL = url
        self.expandedURLs = [url] // Start with root expanded
        self.selectedItemURL = nil
        self.pendingCreation = nil
        self.revealTargetURL = nil
        rebuildTree()
        startWatching(url: url)
    }

    func reveal(_ targetURL: URL) {
        guard rootURL != nil else { return }
        expandToURL(targetURL)
        revealTargetURL = targetURL
        revealRequestID += 1
    }

    /// Expands all ancestor directories from rootURL down to (but not including) targetURL.
    func expandToURL(_ targetURL: URL) {
        guard let rootURL else { return }
        var current = targetURL.deletingLastPathComponent()
        while current.path.hasPrefix(rootURL.path) && current != rootURL {
            expandedURLs.insert(current)
            current = current.deletingLastPathComponent()
        }
        expandedURLs.insert(rootURL)
        rebuildTree() // Refresh to show children of newly expanded folders
    }

    func toggleExpansion(for url: URL) {
        if expandedURLs.contains(url) {
            expandedURLs.remove(url)
        } else {
            expandedURLs.insert(url)
        }
        rebuildTree()
    }

    func setExpansion(for url: URL, isExpanded: Bool) {
        let changed: Bool
        if isExpanded {
            changed = expandedURLs.insert(url).inserted
        } else {
            changed = expandedURLs.remove(url) != nil
        }

        if changed {
            rebuildTree()
        }
    }

    func childrenForDirectory(at url: URL) -> [FileNode]? {
        findNode(for: url)?.children
    }

    var selectedItemIsDirectory: Bool {
        guard let selectedItemURL else { return false }
        return itemExistsAsDirectory(at: selectedItemURL)
    }

    var selectedDirectoryURL: URL? {
        guard let selectedItemURL, selectedItemIsDirectory else { return nil }
        return selectedItemURL
    }

    var canCreateInSelectedDirectory: Bool {
        selectedDirectoryURL != nil
    }

    func selectItem(_ url: URL?) {
        let normalizedURL = url?.standardizedFileURL
        if selectedItemURL != normalizedURL,
           pendingCreation?.parentURL != normalizedURL {
            pendingCreation = nil
        }
        selectedItemURL = normalizedURL
    }

    func beginCreation(kind: FileTreeCreationKind) {
        guard let parentURL = selectedDirectoryURL else { return }
        expandedURLs.insert(parentURL)
        pendingCreation = PendingFileTreeCreation(
            kind: kind,
            parentURL: parentURL
        )
        rebuildTree()
    }

    func updatePendingCreationName(_ name: String) {
        guard pendingCreation != nil else { return }
        pendingCreation?.name = name
        pendingCreation?.validationMessage = nil
    }

    func cancelPendingCreation() {
        pendingCreation = nil
    }

    func pendingCreation(forParent parentURL: URL) -> PendingFileTreeCreation? {
        guard let pendingCreation,
              pendingCreation.parentURL == parentURL.standardizedFileURL else { return nil }
        return pendingCreation
    }

    func insertionIndex(for creation: PendingFileTreeCreation, among nodes: [FileNode]) -> Int {
        let candidateName = comparableDraftName(for: creation)
        return nodes.firstIndex { node in
            comesBefore(
                name: candidateName,
                isDirectory: creation.kind == .folder,
                otherName: node.name,
                otherIsDirectory: node.isDirectory
            )
        } ?? nodes.count
    }

    @discardableResult
    func commitPendingCreation() throws -> FileTreeCreatedItem {
        guard let creation = pendingCreation else {
            throw FileTreeCreationError.noPendingCreation
        }

        do {
            let createdURL = try createItem(kind: creation.kind, in: creation.parentURL, named: creation.name)
            pendingCreation = nil
            selectItem(createdURL)
            reveal(createdURL)
            return FileTreeCreatedItem(kind: creation.kind, url: createdURL)
        } catch {
            pendingCreation?.validationMessage = error.localizedDescription
            throw error
        }
    }

    func rebuildTree() {
        guard let url = rootURL else { return }
        rootNode = buildNode(at: url)
    }

    // MARK: - Tree Building

    /// Builds a node, but ONLY recurses into children if the node is expanded.
    private func buildNode(at url: URL) -> FileNode {
        let name = url.lastPathComponent
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDir {
            let children: [FileNode]?
            if expandedURLs.contains(url) || url == rootURL {
                children = buildChildren(at: url)
            } else {
                children = nil // Lazy load: don't crawl non-expanded folders
            }
            return FileNode(id: url, name: name, url: url, isDirectory: true, children: children)
        } else {
            return FileNode(id: url, name: name, url: url, isDirectory: false, children: nil)
        }
    }

    private func buildChildren(at url: URL) -> [FileNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: showHiddenFiles ? [] : [.skipsHiddenFiles]
        ) else {
            return []
        }

        let nodes = contents.compactMap { childURL -> FileNode? in
            let values = try? childURL.resourceValues(forKeys: resourceKeys)
            let isHidden = values?.isHidden ?? false

            if !showHiddenFiles && isHidden {
                return nil
            }

            return buildNode(at: childURL)
        }

        // Sort: directories first, then alphabetical by name (case-insensitive)
        return nodes.sorted { a, b in
            comesBefore(name: a.name, isDirectory: a.isDirectory, otherName: b.name, otherIsDirectory: b.isDirectory)
        }
    }

    private func findNode(for targetURL: URL) -> FileNode? {
        guard let rootNode else { return nil }
        return findNode(for: targetURL, in: rootNode)
    }

    private func findNode(for targetURL: URL, in node: FileNode) -> FileNode? {
        if node.url == targetURL {
            return node
        }

        guard let children = node.children else { return nil }
        for child in children {
            if let match = findNode(for: targetURL, in: child) {
                return match
            }
        }
        return nil
    }

    private func createItem(kind: FileTreeCreationKind, in parentURL: URL, named rawName: String) throws -> URL {
        guard itemExistsAsDirectory(at: parentURL) else {
            throw FileTreeCreationError.noDirectorySelected
        }

        let name = try validatedCreationName(rawName, in: parentURL)
        let targetURL = parentURL
            .appendingPathComponent(name, isDirectory: kind == .folder)
            .standardizedFileURL

        switch kind {
        case .folder:
            try FileManager.default.createDirectory(
                at: targetURL,
                withIntermediateDirectories: false,
                attributes: nil
            )
        case .file:
            do {
                try Data().write(to: targetURL, options: [.withoutOverwriting])
            } catch CocoaError.fileWriteFileExists {
                throw FileTreeCreationError.alreadyExists(name)
            } catch {
                throw error
            }
        }

        return targetURL
    }

    private func validatedCreationName(_ rawName: String, in parentURL: URL) throws -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw FileTreeCreationError.emptyName
        }
        guard trimmedName != ".", trimmedName != ".." else {
            throw FileTreeCreationError.reservedName
        }
        guard !trimmedName.contains("/"), !trimmedName.contains(":") else {
            throw FileTreeCreationError.invalidCharacters
        }

        let existingURL = parentURL
            .appendingPathComponent(trimmedName, isDirectory: false)
            .standardizedFileURL
        guard !FileManager.default.fileExists(atPath: existingURL.path) else {
            throw FileTreeCreationError.alreadyExists(trimmedName)
        }
        return trimmedName
    }

    private func comparableDraftName(for creation: PendingFileTreeCreation) -> String {
        let trimmedName = creation.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? creation.kind.placeholder : trimmedName
    }

    private func comesBefore(
        name: String,
        isDirectory: Bool,
        otherName: String,
        otherIsDirectory: Bool
    ) -> Bool {
        if isDirectory != otherIsDirectory {
            return isDirectory
        }
        return name.localizedCaseInsensitiveCompare(otherName) == .orderedAscending
    }

    private func itemExistsAsDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    // MARK: - File Watching

    private func startWatching(url: URL) {
        stopWatching()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        // FSEvents callback
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let model = Unmanaged<FileTreeModel>.fromOpaque(info).takeUnretainedValue()
            
            // Only rebuild if any of the changed paths are inside an expanded folder
            // or if the change is to the expanded folder list itself.
            // For simplicity and to avoid missing updates, we rebuild if any expanded path
            // is a prefix of a changed path.
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            
            var shouldRebuild = false
            for path in paths {
                let changedURL = URL(fileURLWithPath: path)
                // If any expanded directory is an ancestor of the change, we need to refresh
                if model.expandedURLs.contains(where: { expanded in
                    changedURL.path.hasPrefix(expanded.path)
                }) {
                    shouldRebuild = true
                    break
                }
            }
            
            if shouldRebuild {
                DispatchQueue.main.async {
                    model.filesystemChangeCount += 1
                    model.rebuildTree()
                }
            }
        }

        let paths = [url.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }
}
