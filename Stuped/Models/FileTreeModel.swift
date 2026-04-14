import Foundation
import Observation

@Observable
class FileTreeModel {
    var rootNode: FileNode?
    var rootURL: URL?
    var showHiddenFiles = false

    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?

    deinit {
        stopWatching()
    }

    func loadDirectory(at url: URL) {
        self.rootURL = url
        rebuildTree()
        startWatching(url: url)
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

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.rebuildTree()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        dispatchSource = source
        source.resume()
    }

    private func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }
}
