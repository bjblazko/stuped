import SwiftUI
import AppKit

struct TabBarView: View {
    var tabManager: TabManager
    let projectRootURL: URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabManager.tabs) { tab in
                    TabCell(
                        tab: tab,
                        isActive: tab.id == tabManager.activeTabID,
                        hasOtherTabs: tabManager.tabs.count > 1,
                        projectRootURL: projectRootURL
                    ) {
                        tabManager.open(url: tab.fileURL)
                    } onClose: {
                        tabManager.close(tab.id)
                    } onCloseOthers: {
                        let others = tabManager.tabs.filter { $0.id != tab.id }.map { $0.id }
                        for id in others { tabManager.close(id) }
                    }
                    Divider().frame(height: 16)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .frame(height: 36)
    }
}

struct CopyPathMenu: View {
    let url: URL
    let projectRootURL: URL?

    var body: some View {
        let relativePath = CopyPathSupport.relativePath(for: url, projectRootURL: projectRootURL)

        return Menu("Copy Path") {
            Button("Name Only") {
                CopyPathSupport.copy(url.lastPathComponent)
            }

            Button("Relative to Project Root") {
                guard let relativePath else { return }
                CopyPathSupport.copy(relativePath)
            }
            .disabled(relativePath == nil)

            Button("Full Path") {
                CopyPathSupport.copy(url.path)
            }
        }
    }
}

enum CopyPathSupport {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func relativePath(for url: URL, projectRootURL: URL?) -> String? {
        guard let projectRootURL else { return nil }

        let standardizedRootURL = projectRootURL.standardizedFileURL.resolvingSymlinksInPath()
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = standardizedRootURL.path
        let candidatePath = standardizedURL.path

        if candidatePath == rootPath {
            return "."
        }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(rootPrefix) else { return nil }

        return String(candidatePath.dropFirst(rootPrefix.count))
    }
}

private struct TabCell: View {
    let tab: TabItem
    let isActive: Bool
    let hasOtherTabs: Bool
    let projectRootURL: URL?
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            if tab.isDirty {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }

            Text(tab.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isActive ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Close Tab", action: onClose)
            Button("Close Others", action: onCloseOthers)
                .disabled(!hasOtherTabs)
            Divider()
            CopyPathMenu(url: tab.fileURL, projectRootURL: projectRootURL)
            Divider()
            Button("Reveal in File Tree") {
                NotificationCenter.default.post(
                    name: .stupedRevealInFileTree,
                    object: nil,
                    userInfo: ["url": tab.fileURL]
                )
            }
        }
    }
}
