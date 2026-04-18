import SwiftUI

struct FileTreeSidebar: View {
    var rootNode: FileNode?
    @Binding var selectedFileURL: URL?
    @Binding var expandedURLs: Set<URL>

    var body: some View {
        Group {
            if let root = rootNode, let children = root.children {
                List(selection: $selectedFileURL) {
                    FileTreeRows(nodes: children, expandedURLs: $expandedURLs)
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
    @Binding var expandedURLs: Set<URL>

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expandedBinding(for: node.url)) {
                    FileTreeRows(nodes: children, expandedURLs: $expandedURLs)
                } label: {
                    nodeLabel(node)
                }
            } else {
                nodeLabel(node)
                    .tag(node.url)
            }
        }
    }

    private func expandedBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { expandedURLs.contains(url) },
            set: { if $0 { expandedURLs.insert(url) } else { expandedURLs.remove(url) } }
        )
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
