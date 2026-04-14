import SwiftUI

struct FileTreeSidebar: View {
    var rootNode: FileNode?
    @Binding var selectedFileURL: URL?

    var body: some View {
        Group {
            if let root = rootNode, let children = root.children {
                List(children, children: \.children, selection: $selectedFileURL) { node in
                    Label(node.name, systemImage: node.iconName)
                        .tag(node.url)
                }
                .listStyle(.sidebar)
            } else {
                ContentUnavailableView("No Folder Open", systemImage: "folder",
                    description: Text("Open a folder to browse its contents."))
            }
        }
    }
}
