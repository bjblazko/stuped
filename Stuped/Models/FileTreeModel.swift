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
    var gitRelevantChangeCount = 0

    private var eventStream: FSEventStreamRef?
    private var scheduledFilesystemRebuild: DispatchWorkItem?
    private let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .nameKey, .isHiddenKey]
    private var nodesByURL: [URL: FileNode] = [:]
    private var childrenByDirectoryURL: [URL: [FileNode]] = [:]
    private let filesystemDrivenRebuildDelay: TimeInterval = 0.5
    private let eventFlagRootChanged = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
    private let eventFlagItemCreated = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
    private let eventFlagItemRemoved = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)
    private let eventFlagItemRenamed = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
    private let eventFlagItemModified = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
    private let eventFlagItemInodeMetaMod = FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod)
    private let eventFlagItemXattrMod = FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod)
    private let eventFlagMustScanSubDirs = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
    private let eventFlagUserDropped = FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
    private let eventFlagKernelDropped = FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
    private let eventFlagItemIsDir = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)
    private let eventFlagOwnEvent = FSEventStreamEventFlags(kFSEventStreamEventFlagOwnEvent)
    private static let watcherTraceURL: URL? = {
        let value = ProcessInfo.processInfo.environment["STUPED_FSEVENT_TRACE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value)
    }()
    private var watcherTraceInitialized = false

    deinit {
        scheduledFilesystemRebuild?.cancel()
        stopWatching()
    }

    func loadDirectory(at url: URL) {
        let normalizedURL = url.standardizedFileURL
        self.rootURL = normalizedURL
        self.expandedURLs = [normalizedURL] // Start with root expanded
        self.selectedItemURL = nil
        self.pendingCreation = nil
        self.revealTargetURL = nil
        self.scheduledFilesystemRebuild?.cancel()
        self.scheduledFilesystemRebuild = nil
        self.watcherTraceInitialized = false
        rebuildTree()
        startWatching(url: normalizedURL)
    }

    func reveal(_ targetURL: URL) {
        let normalizedURL = targetURL.standardizedFileURL
        guard rootURL != nil else { return }
        expandToURL(normalizedURL)
        revealTargetURL = normalizedURL
        revealRequestID += 1
    }

    /// Expands all ancestor directories from rootURL down to (but not including) targetURL.
    func expandToURL(_ targetURL: URL) {
        guard let rootURL else { return }
        let normalizedTargetURL = targetURL.standardizedFileURL
        var current = normalizedTargetURL.deletingLastPathComponent()
        while current.path.hasPrefix(rootURL.path) && current != rootURL {
            expandedURLs.insert(current)
            current = current.deletingLastPathComponent()
        }
        expandedURLs.insert(rootURL)
        rebuildTree() // Refresh to show children of newly expanded folders
    }

    func toggleExpansion(for url: URL) {
        let normalizedURL = url.standardizedFileURL
        if expandedURLs.contains(normalizedURL) {
            expandedURLs.remove(normalizedURL)
        } else {
            expandedURLs.insert(normalizedURL)
        }
        rebuildTree()
    }

    func setExpansion(for url: URL, isExpanded: Bool) {
        let normalizedURL = url.standardizedFileURL
        let changed: Bool
        if isExpanded {
            changed = expandedURLs.insert(normalizedURL).inserted
        } else {
            changed = expandedURLs.remove(normalizedURL) != nil
        }

        if changed {
            rebuildTree()
        }
    }

    func childrenForDirectory(at url: URL) -> [FileNode]? {
        childrenByDirectoryURL[url.standardizedFileURL]
    }

    var selectedItemIsDirectory: Bool {
        guard let selectedItemURL else { return false }
        if let node = nodesByURL[selectedItemURL.standardizedFileURL] {
            return node.isDirectory
        }
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
        guard let url = rootURL else {
            rootNode = nil
            nodesByURL.removeAll()
            childrenByDirectoryURL.removeAll()
            return
        }

        var nodesByURL: [URL: FileNode] = [:]
        var childrenByDirectoryURL: [URL: [FileNode]] = [:]
        let rootNode = buildNode(
            at: url,
            nodesByURL: &nodesByURL,
            childrenByDirectoryURL: &childrenByDirectoryURL
        )

        self.rootNode = rootNode
        self.nodesByURL = nodesByURL
        self.childrenByDirectoryURL = childrenByDirectoryURL
    }

    // MARK: - Tree Building

    /// Builds a node, but ONLY recurses into children if the node is expanded.
    private func buildNode(
        at url: URL,
        nodesByURL: inout [URL: FileNode],
        childrenByDirectoryURL: inout [URL: [FileNode]]
    ) -> FileNode {
        let normalizedURL = url.standardizedFileURL
        let name = normalizedURL.lastPathComponent
        let isDir = (try? normalizedURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDir {
            let children: [FileNode]?
            if expandedURLs.contains(normalizedURL) || normalizedURL == rootURL {
                children = buildChildren(
                    at: normalizedURL,
                    nodesByURL: &nodesByURL,
                    childrenByDirectoryURL: &childrenByDirectoryURL
                )
            } else {
                children = nil // Lazy load: don't crawl non-expanded folders
            }
            let node = FileNode(
                id: normalizedURL,
                name: name,
                url: normalizedURL,
                isDirectory: true,
                children: children
            )
            nodesByURL[normalizedURL] = node
            if let children {
                childrenByDirectoryURL[normalizedURL] = children
            }
            return node
        } else {
            let node = FileNode(
                id: normalizedURL,
                name: name,
                url: normalizedURL,
                isDirectory: false,
                children: nil
            )
            nodesByURL[normalizedURL] = node
            return node
        }
    }

    private func buildChildren(
        at url: URL,
        nodesByURL: inout [URL: FileNode],
        childrenByDirectoryURL: inout [URL: [FileNode]]
    ) -> [FileNode] {
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

            return buildNode(
                at: childURL,
                nodesByURL: &nodesByURL,
                childrenByDirectoryURL: &childrenByDirectoryURL
            )
        }

        // Sort: directories first, then alphabetical by name (case-insensitive)
        return nodes.sorted { a, b in
            comesBefore(name: a.name, isDirectory: a.isDirectory, otherName: b.name, otherIsDirectory: b.isDirectory)
        }
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
        (try? url.standardizedFileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private func fileSystemEventDecision(
        for changedURL: URL,
        flags: FSEventStreamEventFlags
    ) -> (rebuildTree: Bool, refreshGit: Bool) {
        guard let rootURL else { return (false, false) }

        let normalizedChangedURL = changedURL.standardizedFileURL
        let rootPath = rootURL.path
        let changedPath = normalizedChangedURL.path
        guard changedPath == rootPath || changedPath.hasPrefix(rootPath + "/") else {
            return (false, false)
        }

        return (
            rebuildTree: shouldRebuildTree(for: normalizedChangedURL, flags: flags, rootURL: rootURL),
            refreshGit: shouldRefreshGit(for: normalizedChangedURL, flags: flags, rootURL: rootURL)
        )
    }

    private func shouldRebuildTree(
        for changedURL: URL,
        flags: FSEventStreamEventFlags,
        rootURL: URL
    ) -> Bool {
        if hasFlag(flags, eventFlagRootChanged) {
            return true
        }
        guard isStructuralEvent(flags) else { return false }
        guard showHiddenFiles || !containsHiddenComponent(in: changedURL, relativeTo: rootURL) else {
            return false
        }
        if changedURL == rootURL {
            return true
        }

        let parentURL = changedURL.deletingLastPathComponent().standardizedFileURL
        return expandedURLs.contains(parentURL)
    }

    private func shouldRefreshGit(
        for changedURL: URL,
        flags: FSEventStreamEventFlags,
        rootURL: URL
    ) -> Bool {
        if isRelevantGitMetadataChange(for: changedURL, relativeTo: rootURL) {
            return true
        }

        return isStructuralEvent(flags)
            || hasFlag(flags, eventFlagItemModified)
            || hasFlag(flags, eventFlagItemInodeMetaMod)
            || hasFlag(flags, eventFlagItemXattrMod)
    }

    private func isStructuralEvent(_ flags: FSEventStreamEventFlags) -> Bool {
        hasFlag(flags, eventFlagItemCreated)
            || hasFlag(flags, eventFlagItemRemoved)
            || hasFlag(flags, eventFlagItemRenamed)
            || hasFlag(flags, eventFlagRootChanged)
    }

    private func hasFlag(_ flags: FSEventStreamEventFlags, _ flag: FSEventStreamEventFlags) -> Bool {
        (flags & flag) != 0
    }

    private func containsHiddenComponent(in url: URL, relativeTo rootURL: URL) -> Bool {
        guard let relativeComponents = relativePathComponents(for: url, relativeTo: rootURL) else {
            return false
        }
        return relativeComponents.contains { component in
            component.hasPrefix(".") && component != "." && component != ".."
        }
    }

    private func isRelevantGitMetadataChange(for url: URL, relativeTo rootURL: URL) -> Bool {
        guard let relativeComponents = relativePathComponents(for: url, relativeTo: rootURL),
              let gitIndex = relativeComponents.firstIndex(of: ".git") else {
            return false
        }

        let tail = Array(relativeComponents.dropFirst(gitIndex + 1))
        guard let first = tail.first else { return true }
        if first == "HEAD" || first == "index" || first == "packed-refs" {
            return true
        }
        return first == "refs"
    }

    private func relativePathComponents(for url: URL, relativeTo rootURL: URL) -> [String]? {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count >= rootComponents.count else { return nil }
        return Array(urlComponents.dropFirst(rootComponents.count))
    }

    private func scheduleFilesystemDrivenRebuild() {
        scheduledFilesystemRebuild?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledFilesystemRebuild = nil
            self.rebuildTree()
        }

        scheduledFilesystemRebuild = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + filesystemDrivenRebuildDelay,
            execute: workItem
        )
    }

    private func traceWatcherEvent(
        path: String,
        flags: FSEventStreamEventFlags,
        decision: (rebuildTree: Bool, refreshGit: Bool)
    ) {
        guard let traceURL = Self.watcherTraceURL,
              decision.rebuildTree || decision.refreshGit else { return }

        if !watcherTraceInitialized {
            FileManager.default.createFile(atPath: traceURL.path, contents: nil)
            watcherTraceInitialized = true
        }

        let line = [
            Date().ISO8601Format(),
            "path=\(path)",
            "flags=\(formattedEventFlags(flags))",
            "rebuild=\(decision.rebuildTree)",
            "git=\(decision.refreshGit)"
        ].joined(separator: " ")

        guard let data = (line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: traceURL) else { return }

        defer {
            try? handle.close()
        }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func formattedEventFlags(_ flags: FSEventStreamEventFlags) -> String {
        var names: [String] = []

        if hasFlag(flags, eventFlagRootChanged) { names.append("rootChanged") }
        if hasFlag(flags, eventFlagItemCreated) { names.append("created") }
        if hasFlag(flags, eventFlagItemRemoved) { names.append("removed") }
        if hasFlag(flags, eventFlagItemRenamed) { names.append("renamed") }
        if hasFlag(flags, eventFlagItemModified) { names.append("modified") }
        if hasFlag(flags, eventFlagItemInodeMetaMod) { names.append("inodeMeta") }
        if hasFlag(flags, eventFlagItemXattrMod) { names.append("xattr") }
        if hasFlag(flags, eventFlagMustScanSubDirs) { names.append("mustScanSubDirs") }
        if hasFlag(flags, eventFlagUserDropped) { names.append("userDropped") }
        if hasFlag(flags, eventFlagKernelDropped) { names.append("kernelDropped") }
        if hasFlag(flags, eventFlagItemIsDir) { names.append("isDir") }
        if hasFlag(flags, eventFlagOwnEvent) { names.append("ownEvent") }

        if names.isEmpty {
            return String(format: "0x%08llx", UInt64(flags))
        }

        return names.joined(separator: ",")
    }

    private var watcherQueue = DispatchQueue(label: "com.stuped.file-watching", qos: .utility)

    // MARK: - File Watching

    private func startWatching(url: URL) {
        stopWatching()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        // FSEvents callback
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let model = Unmanaged<FileTreeModel>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            let flagsBuffer = UnsafeBufferPointer(start: eventFlags, count: Int(numEvents))

            var shouldRebuildTree = false
            var shouldRefreshGit = false

            for index in 0..<min(paths.count, flagsBuffer.count) {
                let decision = model.fileSystemEventDecision(
                    for: URL(fileURLWithPath: paths[index]),
                    flags: flagsBuffer[index]
                )
                model.traceWatcherEvent(
                    path: paths[index],
                    flags: flagsBuffer[index],
                    decision: decision
                )
                shouldRebuildTree = shouldRebuildTree || decision.rebuildTree
                shouldRefreshGit = shouldRefreshGit || decision.refreshGit
                if shouldRebuildTree && shouldRefreshGit {
                    break
                }
            }

            guard shouldRebuildTree || shouldRefreshGit else { return }
            
            DispatchQueue.main.async {
                if shouldRefreshGit {
                    model.gitRelevantChangeCount += 1
                }
                if shouldRebuildTree {
                    model.scheduleFilesystemDrivenRebuild()
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

        FSEventStreamSetDispatchQueue(stream, watcherQueue)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func stopWatching() {
        scheduledFilesystemRebuild?.cancel()
        scheduledFilesystemRebuild = nil
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }
}
