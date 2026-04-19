import Foundation

@Observable
final class TabManager {
    var tabs: [TabItem] = []
    var activeTabID: TabItem.ID?
    /// Tab IDs ordered from most-recently to least-recently accessed (index 0 = current).
    var recentTabIDs: [TabItem.ID] = []

    private var watchedFDs: [TabItem.ID: (fd: Int32, source: DispatchSourceFileSystemObject)] = [:]

    var activeTab: TabItem? {
        tabs.first { $0.id == activeTabID }
    }

    /// Tabs sorted by most-recently accessed (most recent first).
    var tabsByRecency: [TabItem] {
        recentTabIDs.compactMap { id in tabs.first { $0.id == id } }
    }

    /// Opens a file: switches to it if already open, otherwise loads from disk and creates a new tab.
    /// Posts `.stupedTabSwitched` only when switching to an existing tab (new tabs are handled
    /// by ContentView's onChange flow).
    func open(url: URL) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return
        }

        if let existing = tabs.first(where: { $0.fileURL == url }) {
            guard activeTabID != existing.id else { return }
            activeTabID = existing.id
            recordAccess(existing.id)
            NotificationCenter.default.post(
                name: .stupedTabSwitched,
                object: nil,
                userInfo: ["url": url]
            )
            return
        }

        let text = Self.loadText(from: url)
        let tab = TabItem(fileURL: url, text: text)
        tabs.append(tab)
        startWatching(tab)
        activeTabID = tab.id
        recordAccess(tab.id)
        NotificationCenter.default.post(
            name: .stupedTabSwitched,
            object: nil,
            userInfo: ["url": url]
        )
    }

    private func recordAccess(_ id: TabItem.ID) {
        recentTabIDs.removeAll { $0 == id }
        recentTabIDs.insert(id, at: 0)
    }

    func close(_ id: TabItem.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        stopWatching(id)
        tabs.remove(at: idx)

        guard wasActive else { return }

        if tabs.isEmpty {
            activeTabID = nil
        } else {
            let newIdx = min(idx, tabs.count - 1)
            let next = tabs[newIdx]
            activeTabID = next.id
            NotificationCenter.default.post(
                name: .stupedTabSwitched,
                object: nil,
                userInfo: ["url": next.fileURL]
            )
        }
    }

    func markActiveSaved() {
        activeTab?.markSaved()
    }

    func clearAll() {
        stopAllWatchers()
        tabs.removeAll()
        activeTabID = nil
        recentTabIDs.removeAll()
    }

    // MARK: - File watching

    private func startWatching(_ tab: TabItem) {
        let fd = Darwin.open(tab.fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self, weak tab] in
            guard let self, let tab else { return }
            let mask = source.data
            if mask.contains(.write) && !tab.isDirty {
                let fresh = Self.loadText(from: tab.fileURL)
                tab.text = fresh
                tab.savedText = fresh
            }
            if mask.contains(.rename) || mask.contains(.delete) {
                self.stopWatching(tab.id)
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        watchedFDs[tab.id] = (fd, source)
    }

    private func stopWatching(_ id: TabItem.ID) {
        watchedFDs.removeValue(forKey: id)?.source.cancel()
    }

    private func stopAllWatchers() {
        watchedFDs.values.forEach { $0.source.cancel() }
        watchedFDs.removeAll()
    }

    // MARK: - File loading

    private static func loadText(from url: URL) -> String {
        guard !LanguageMap.isImage(url.pathExtension) else { return "" }
        do {
            let data = try Data(contentsOf: url)
            let checkLength = min(data.count, 8192)
            if data.prefix(checkLength).contains(0x00) {
                return "[Binary file — cannot display]"
            }
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "Error loading file: \(error.localizedDescription)"
        }
    }
}

extension Notification.Name {
    static let stupedTabSwitched = Notification.Name("stupedTabSwitched")
}
