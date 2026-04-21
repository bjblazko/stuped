import Foundation

@Observable
final class TabManager {
    var tabs: [TabItem] = []
    var activeTabID: TabItem.ID?
    /// Tab IDs ordered from most-recently to least-recently accessed (index 0 = current).
    var recentTabIDs: [TabItem.ID] = []
    /// Linear file-navigation history for the current folder-browsing session.
    private(set) var historyURLs: [URL] = []
    private(set) var historyIndex: Int?

    private var watchedFDs: [TabItem.ID: (fd: Int32, source: DispatchSourceFileSystemObject)] = [:]

    var activeTab: TabItem? {
        tabs.first { $0.id == activeTabID }
    }

    /// Tabs sorted by most-recently accessed (most recent first).
    var tabsByRecency: [TabItem] {
        recentTabIDs.compactMap { id in tabs.first { $0.id == id } }
    }

    var canGoBack: Bool {
        guard let historyIndex else { return false }
        return historyIndex > 0
    }

    var canGoForward: Bool {
        guard let historyIndex else { return false }
        return historyIndex < historyURLs.count - 1
    }

    /// Unique file URLs ordered with the current history item first, then the
    /// remaining session history from most-recently visited to least-recently visited.
    var historyURLsByRecency: [URL] {
        var seenPaths = Set<String>()
        var urls: [URL] = []

        if let historyIndex, historyURLs.indices.contains(historyIndex) {
            let currentURL = historyURLs[historyIndex]
            seenPaths.insert(currentURL.path)
            urls.append(currentURL)
        }

        for url in historyURLs.reversed() {
            if seenPaths.insert(url.path).inserted {
                urls.append(url)
            }
        }

        return urls
    }

    /// Opens a file: switches to it if already open, otherwise loads from disk and creates a new tab.
    /// Posts `.stupedTabSwitched` only when switching to an existing tab (new tabs are handled
    /// by ContentView's onChange flow).
    @discardableResult
    func open(url: URL, trackHistory: Bool = true) -> Bool {
        let normalizedURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        if let existing = tabs.first(where: { $0.fileURL == normalizedURL }) {
            guard activeTabID != existing.id else {
                if trackHistory {
                    recordHistory(normalizedURL)
                }
                return true
            }

            activeTabID = existing.id
            recordAccess(existing.id)
            if trackHistory {
                recordHistory(normalizedURL)
            }
            NotificationCenter.default.post(
                name: .stupedTabSwitched,
                object: nil,
                userInfo: ["url": normalizedURL]
            )
            return true
        }

        let text = Self.loadText(from: normalizedURL)
        let tab = TabItem(fileURL: normalizedURL, text: text)
        tabs.append(tab)
        startWatching(tab)
        activeTabID = tab.id
        recordAccess(tab.id)
        if trackHistory {
            recordHistory(normalizedURL)
        }
        NotificationCenter.default.post(
            name: .stupedTabSwitched,
            object: nil,
            userInfo: ["url": normalizedURL]
        )
        return true
    }

    private func recordAccess(_ id: TabItem.ID) {
        recentTabIDs.removeAll { $0 == id }
        recentTabIDs.insert(id, at: 0)
    }

    private func recordHistory(_ url: URL) {
        if let historyIndex, historyURLs.indices.contains(historyIndex), historyURLs[historyIndex] == url {
            return
        }

        if let historyIndex, historyIndex < historyURLs.count - 1 {
            historyURLs.removeSubrange((historyIndex + 1)...)
        }

        historyURLs.append(url)
        self.historyIndex = historyURLs.count - 1
    }

    @discardableResult
    func goBack() -> Bool {
        navigateHistory(by: -1)
    }

    @discardableResult
    func goForward() -> Bool {
        navigateHistory(by: 1)
    }

    @discardableResult
    private func navigateHistory(by delta: Int) -> Bool {
        guard let historyIndex else { return false }
        let targetIndex = historyIndex + delta
        return navigateHistory(to: targetIndex)
    }

    @discardableResult
    private func navigateHistory(to targetIndex: Int) -> Bool {
        guard historyURLs.indices.contains(targetIndex) else { return false }
        let targetURL = historyURLs[targetIndex]
        guard open(url: targetURL, trackHistory: false) else { return false }
        historyIndex = targetIndex
        return true
    }

    func close(_ id: TabItem.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        stopWatching(id)
        tabs.remove(at: idx)

        guard wasActive else { return }

        if tabs.isEmpty {
            activeTabID = nil
            NotificationCenter.default.post(name: .stupedTabSwitched, object: nil)
        } else {
            let newIdx = min(idx, tabs.count - 1)
            let next = tabs[newIdx]
            activeTabID = next.id
            recordAccess(next.id)
            recordHistory(next.fileURL)
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
        historyURLs.removeAll()
        historyIndex = nil
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
