import SwiftUI

struct FileTreeSidebar: View {
    @Bindable var model: FileTreeModel
    @Binding var selectedFileURL: URL?
    let projectRootURL: URL?

    var body: some View {
        Group {
            if let root = model.rootNode, let children = root.children {
                ScrollViewReader { proxy in
                    List {
                        FileTreeRows(
                            nodes: children,
                            model: model,
                            selectedFileURL: $selectedFileURL,
                            projectRootURL: projectRootURL
                        )
                    }
                    .listStyle(.sidebar)
                    .task(id: model.revealRequestID) {
                        await scrollToRevealTarget(using: proxy)
                    }
                }
            } else {
                ContentUnavailableView("No Folder Open", systemImage: "folder",
                    description: Text("Open a folder to browse its contents."))
            }
        }
    }

    @MainActor
    private func scrollToRevealTarget(using proxy: ScrollViewProxy) async {
        guard model.revealRequestID > 0, let targetURL = model.revealTargetURL else { return }
        await Task.yield()
        withAnimation {
            proxy.scrollTo(targetURL, anchor: .center)
        }
    }
}

private struct FileTreeRows: View {
    let nodes: [FileNode]
    @Bindable var model: FileTreeModel
    @Binding var selectedFileURL: URL?
    let projectRootURL: URL?

    var body: some View {
        ForEach(nodes) { node in
            if node.isDirectory {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { model.expandedURLs.contains(node.url) },
                        set: { isExpanded in
                            model.setExpansion(for: node.url, isExpanded: isExpanded)
                        }
                    )
                ) {
                    if let children = model.childrenForDirectory(at: node.url) {
                        FileTreeRows(
                            nodes: children,
                            model: model,
                            selectedFileURL: $selectedFileURL,
                            projectRootURL: projectRootURL
                        )
                    } else {
                        ProgressView().controlSize(.small).padding(.leading)
                    }
                } label: {
                    nodeLabel(node)
                }
                .id(node.url)
            } else {
                nodeLabel(node)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFileURL = node.url
                    }
                    .listRowBackground(
                        selectedFileURL == node.url
                            ? Color(nsColor: .selectedContentBackgroundColor)
                            : Color.clear
                    )
                    .id(node.url)
            }
        }
    }

    private func nodeLabel(_ node: FileNode) -> some View {
        Label {
            Text(node.name)
        } icon: {
            Image(systemName: node.iconName)
                .foregroundStyle(node.iconColor)
        }
        .contentShape(Rectangle())
        .contextMenu {
            CopyPathMenu(url: node.url, projectRootURL: projectRootURL)
        }
    }
}
