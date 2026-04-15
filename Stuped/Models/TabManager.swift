import Foundation

@Observable
final class TabManager {
    var tabs: [TabItem] = []
    var activeTabID: TabItem.ID?
    /// Tab IDs ordered from most-recently to least-recently accessed (index 0 = current).
    var recentTabIDs: [TabItem.ID] = []

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
        tabs.removeAll()
        activeTabID = nil
        recentTabIDs.removeAll()
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
