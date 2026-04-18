import SwiftUI

struct TabBarView: View {
    var tabManager: TabManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabManager.tabs) { tab in
                    TabCell(
                        tab: tab,
                        isActive: tab.id == tabManager.activeTabID,
                        hasOtherTabs: tabManager.tabs.count > 1
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

private struct TabCell: View {
    let tab: TabItem
    let isActive: Bool
    let hasOtherTabs: Bool
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
