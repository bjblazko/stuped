import SwiftUI
import AppKit

private enum RecentItemKind: String {
    case openFile
    case recentFile
    case recentFolder
}

private struct RecentItem: Identifiable {
    let url: URL
    let kind: RecentItemKind
    var id: String { "\(kind.rawValue)::\(url.path)" }
}

/// Floating command-palette popup for switching between open tabs and recently used files/folders.
/// Triggered by Cmd+R in folder mode.
struct RecentItemsPopupView: View {
    let tabManager: TabManager
    @Bindable var recentFoldersStore: RecentFoldersStore
    @Binding var isShowing: Bool
    /// Incremented by the parent each time Cmd+R is pressed while the popup is visible;
    /// causes the selection to advance by one row.
    let cycleTrigger: Int
    let onSelectFile: (URL) -> Void
    let onSelectFolder: (URL) -> Void

    @State private var selectedIndex: Int
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(
        tabManager: TabManager,
        recentFoldersStore: RecentFoldersStore,
        isShowing: Binding<Bool>,
        initialSelectedIndex: Int,
        cycleTrigger: Int,
        onSelectFile: @escaping (URL) -> Void,
        onSelectFolder: @escaping (URL) -> Void
    ) {
        self.tabManager = tabManager
        self.recentFoldersStore = recentFoldersStore
        self._isShowing = isShowing
        self.cycleTrigger = cycleTrigger
        self.onSelectFile = onSelectFile
        self.onSelectFolder = onSelectFolder
        self._selectedIndex = State(initialValue: initialSelectedIndex)
    }

    // MARK: - Data

    private var filteredItems: [RecentItem] {
        let openURLs = Set(tabManager.tabs.map(\.fileURL))
        let sessionHistoryURLs = tabManager.historyURLsByRecency
        let sessionHistoryPaths = Set(sessionHistoryURLs.map(\.path))

        let sessionHistoryItems = sessionHistoryURLs.map { url in
            let kind: RecentItemKind = openURLs.contains(url) ? .openFile : .recentFile
            return RecentItem(url: url, kind: kind)
        }

        let recentFileItems = NSDocumentController.shared.recentDocumentURLs
            .map(\.standardizedFileURL)
            .filter { !sessionHistoryPaths.contains($0.path) }
            .prefix(10)
            .map { RecentItem(url: $0, kind: .recentFile) }

        let recentFolderItems = recentFoldersStore.recentFolders
            .prefix(10)
            .map { RecentItem(url: $0, kind: .recentFolder) }

        let all = sessionHistoryItems + recentFileItems + recentFolderItems

        guard !searchText.isEmpty else { return all }
        let lower = searchText.lowercased()
        return all.filter { item in
            item.url.lastPathComponent.lowercased().contains(lower)
                || locationText(for: item).lowercased().contains(lower)
        }
    }

    private var effectiveIndex: Int {
        guard !filteredItems.isEmpty else { return 0 }
        return min(selectedIndex, filteredItems.count - 1)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { isShowing = false }

            popupCard
                .frame(width: 420)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { searchFocused = true }
        .onChange(of: cycleTrigger) { _, _ in
            guard !filteredItems.isEmpty else { return }
            selectedIndex = (effectiveIndex + 1) % filteredItems.count
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Popup card

    private var popupCard: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            fileList
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField("Search open and recent files/folders…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    confirmSelection()
                    return .handled
                }
                .onKeyPress(.escape) {
                    isShowing = false
                    return .handled
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var fileList: some View {
        if filteredItems.isEmpty {
            Text("No recent files or folders")
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(20)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { idx, item in
                            FileRowView(item: item, isSelected: idx == effectiveIndex)
                                .id(idx)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    select(item)
                                    isShowing = false
                                }
                        }
                    }
                }
                .frame(maxHeight: 280)
                .onChange(of: effectiveIndex) { _, newIdx in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func moveSelection(by delta: Int) {
        guard !filteredItems.isEmpty else { return }
        selectedIndex = (effectiveIndex + delta + filteredItems.count) % filteredItems.count
    }

    private func confirmSelection() {
        guard !filteredItems.isEmpty else { return }
        select(filteredItems[effectiveIndex])
        isShowing = false
    }

    private func select(_ item: RecentItem) {
        switch item.kind {
        case .recentFolder:
            onSelectFolder(item.url)
        case .openFile, .recentFile:
            onSelectFile(item.url)
        }
    }

    private func locationText(for item: RecentItem) -> String {
        switch item.kind {
        case .recentFolder:
            return abbreviatedPath(item.url.path)
        case .openFile, .recentFile:
            return abbreviatedPath(item.url.deletingLastPathComponent().path)
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Row view

private struct FileRowView: View {
    let item: RecentItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(titleText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(locationText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(badgeBackground, in: Capsule())
                    .foregroundStyle(badgeForeground)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
            }
        }
    }

    private var fileIcon: NSImage {
        let path = item.url.path
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    private var titleText: String {
        item.url.lastPathComponent
    }

    private var locationText: String {
        let path: String
        switch item.kind {
        case .recentFolder:
            path = item.url.path
        case .openFile, .recentFile:
            path = item.url.deletingLastPathComponent().path
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private var badgeText: String? {
        switch item.kind {
        case .openFile:
            return "open"
        case .recentFolder:
            return "folder"
        case .recentFile:
            return nil
        }
    }

    private var badgeBackground: Color {
        switch item.kind {
        case .openFile:
            return Color.accentColor.opacity(0.15)
        case .recentFolder:
            return Color.secondary.opacity(0.14)
        case .recentFile:
            return .clear
        }
    }

    private var badgeForeground: Color {
        switch item.kind {
        case .openFile:
            return Color.accentColor
        case .recentFolder:
            return Color.secondary
        case .recentFile:
            return .clear
        }
    }
}
