import SwiftUI

struct FileTreeSidebar: View {
    @Bindable var model: FileTreeModel
    @Binding var selectedFileURL: URL?

    var body: some View {
        Group {
            if let root = model.rootNode, let children = root.children {
                List(selection: $selectedFileURL) {
                    FileTreeRows(nodes: children, model: model)
                }
                .listStyle(.sidebar)
            } else {
                ContentUnavailableView("No Folder Open", systemImage: "folder",
                    description: Text("Open a folder to browse its contents."))
            }
        }
    }
}

private struct FileTreeRows: View {
    let nodes: [FileNode]
    let model: FileTreeModel

    var body: some View {
        ForEach(nodes) { node in
            if node.isDirectory {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { model.expandedURLs.contains(node.url) },
                        set: { _ in model.toggleExpansion(for: node.url) }
                    )
                ) {
                    if let children = node.children {
                        FileTreeRows(nodes: children, model: model)
                    } else {
                        // This state should ideally not be reached with lazy loading
                        // if building children on expansion, but provides a fallback.
                        ProgressView().controlSize(.small).padding(.leading)
                    }
                } label: {
                    nodeLabel(node)
                }
            } else {
                nodeLabel(node)
                    .tag(node.url)
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
    }
}
