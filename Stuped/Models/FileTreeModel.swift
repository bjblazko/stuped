import Foundation
import Observation
import CoreServices

@Observable
class FileTreeModel {
    var rootNode: FileNode?
    var rootURL: URL?
    var showHiddenFiles = false
    var expandedURLs: Set<URL> = []

    private var eventStream: FSEventStreamRef?
    private let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .nameKey, .isHiddenKey]

    deinit {
        stopWatching()
    }

    func loadDirectory(at url: URL) {
        self.rootURL = url
        self.expandedURLs = [url] // Start with root expanded
        rebuildTree()
        startWatching(url: url)
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
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
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
