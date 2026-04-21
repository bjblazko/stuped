import SwiftUI

struct FileTreeSidebar: View {
    @Bindable var model: FileTreeModel
    @Binding var selectedFileURL: URL?
    let projectRootURL: URL?

    var body: some View {
        Group {
            if let root = model.rootNode, let children = root.children {
                List {
                    FileTreeRows(
                        nodes: children,
                        model: model,
                        selectedFileURL: $selectedFileURL,
                        projectRootURL: projectRootURL
                    )
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
