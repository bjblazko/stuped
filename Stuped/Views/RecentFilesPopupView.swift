import SwiftUI
import AppKit

private struct RecentFilesItem: Identifiable {
    let url: URL
    let isOpen: Bool
    var id: URL { url }
}

/// Floating command-palette popup for switching between open tabs and recently opened files.
/// Triggered by Cmd+R in folder mode.
struct RecentFilesPopupView: View {
    let tabManager: TabManager
    @Binding var isShowing: Bool
    /// Incremented by the parent each time Cmd+R is pressed while the popup is visible;
    /// causes the selection to advance by one row.
    let cycleTrigger: Int
    let onSelect: (URL) -> Void

    @State private var selectedIndex: Int
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    init(
        tabManager: TabManager,
        isShowing: Binding<Bool>,
        initialSelectedIndex: Int,
        cycleTrigger: Int,
        onSelect: @escaping (URL) -> Void
    ) {
        self.tabManager = tabManager
        self._isShowing = isShowing
        self.cycleTrigger = cycleTrigger
        self.onSelect = onSelect
        self._selectedIndex = State(initialValue: initialSelectedIndex)
    }

    // MARK: - Data

    private var filteredItems: [RecentFilesItem] {
        let openURLs = Set(tabManager.tabs.map(\.fileURL))

        let openItems = tabManager.tabsByRecency
            .map { RecentFilesItem(url: $0.fileURL, isOpen: true) }

        let recentItems = NSDocumentController.shared.recentDocumentURLs
            .filter { !openURLs.contains($0) }
            .prefix(10)
            .map { RecentFilesItem(url: $0, isOpen: false) }

        let all = openItems + recentItems

        guard !searchText.isEmpty else { return all }
        let lower = searchText.lowercased()
        return all.filter { $0.url.lastPathComponent.lowercased().contains(lower) }
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
            TextField("Search open and recent files…", text: $searchText)
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
            Text("No recent files")
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
                                    onSelect(item.url)
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
        onSelect(filteredItems[effectiveIndex].url)
        isShowing = false
    }
}

// MARK: - Row view

private struct FileRowView: View {
    let item: RecentFilesItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(abbreviatedDirectory)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.isOpen {
                Text("open")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
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

    private var abbreviatedDirectory: String {
        let dir = item.url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            return "~" + dir.dropFirst(home.count)
        }
        return dir
    }
}
