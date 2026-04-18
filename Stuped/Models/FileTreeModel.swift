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

    deinit {
        stopWatching()
    }

    func loadDirectory(at url: URL) {
        self.rootURL = url
        self.expandedURLs = []
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
    }

    func rebuildTree() {
        guard let url = rootURL else { return }
        rootNode = buildNode(at: url)
    }

    // MARK: - Tree Building

    private func buildNode(at url: URL) -> FileNode {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .nameKey, .isHiddenKey]
        let name = url.lastPathComponent
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDir {
            let children = buildChildren(at: url, resourceKeys: resourceKeys)
            return FileNode(id: url, name: name, url: url, isDirectory: true, children: children)
        } else {
            return FileNode(id: url, name: name, url: url, isDirectory: false, children: nil)
        }
    }

    private func buildChildren(at url: URL, resourceKeys: Set<URLResourceKey>) -> [FileNode] {
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

    // MARK: - File Watching

    private func startWatching(url: URL) {
        stopWatching()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileTreeModel>.fromOpaque(info).takeUnretainedValue().rebuildTree()
        }

        let paths = [url.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
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
