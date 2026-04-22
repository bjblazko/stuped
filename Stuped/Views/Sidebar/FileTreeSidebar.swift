import SwiftUI
import AppKit

struct FileTreeSidebar: View {
    @Bindable var model: FileTreeModel
    @Binding var selectedFileURL: URL?
    let projectRootURL: URL?
    let gitStatusSnapshot: GitWorkingTreeStatusSnapshot?
    let onCreateItem: (FileTreeCreationKind) -> Void
    let onCommitCreation: () -> Void

    var body: some View {
        Group {
            if let root = model.rootNode, let children = root.children {
                ScrollViewReader { proxy in
                    List {
                        FileTreeRows(
                            nodes: children,
                            model: model,
                            selectedFileURL: $selectedFileURL,
                            projectRootURL: projectRootURL,
                            gitStatusSnapshot: gitStatusSnapshot,
                            onCreateItem: onCreateItem,
                            onCommitCreation: onCommitCreation
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
    let gitStatusSnapshot: GitWorkingTreeStatusSnapshot?
    let onCreateItem: (FileTreeCreationKind) -> Void
    let onCommitCreation: () -> Void

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
                        FileTreeDirectoryContents(
                            parentURL: node.url,
                            children: children,
                            model: model,
                            selectedFileURL: $selectedFileURL,
                            projectRootURL: projectRootURL,
                            gitStatusSnapshot: gitStatusSnapshot,
                            onCreateItem: onCreateItem,
                            onCommitCreation: onCommitCreation
                        )
                    } else {
                        ProgressView().controlSize(.small).padding(.leading)
                    }
                } label: {
                    nodeLabel(node)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    model.selectItem(node.url)
                })
                .listRowBackground(rowBackground(for: node))
                .id(node.url)
            } else {
                nodeLabel(node)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectItem(node.url)
                        selectedFileURL = node.url
                    }
                    .listRowBackground(rowBackground(for: node))
                    .id(node.url)
            }
        }
    }

    private func nodeLabel(_ node: FileNode) -> some View {
        let changeKind = gitChangeKind(for: node)
        let isSelected = model.selectedItemURL == node.url

        return Label {
            Text(node.name)
                .foregroundStyle(titleColor(for: node, changeKind: changeKind, isSelected: isSelected))
        } icon: {
            FileTreeNodeIcon(node: node, changeKind: changeKind)
        }
        .contentShape(Rectangle())
        .contextMenu {
            CopyPathMenu(url: node.url, projectRootURL: projectRootURL)
            Divider()
            Button(FileTreeCreationKind.file.menuTitle) {
                onCreateItem(.file)
            }
            .disabled(!model.canCreateInSelectedDirectory)

            Button(FileTreeCreationKind.folder.menuTitle) {
                onCreateItem(.folder)
            }
            .disabled(!model.canCreateInSelectedDirectory)
        }
    }

    private func rowBackground(for node: FileNode) -> Color {
        model.selectedItemURL == node.url
            ? Color(nsColor: .selectedContentBackgroundColor)
            : .clear
    }

    private func gitChangeKind(for node: FileNode) -> GitWorkingTreeChangeKind? {
        guard !node.isDirectory else { return nil }
        return gitStatusSnapshot?.changeKind(for: node.url)
    }

    private func titleColor(
        for node: FileNode,
        changeKind: GitWorkingTreeChangeKind?,
        isSelected: Bool
    ) -> Color {
        if isSelected {
            return Color(nsColor: .selectedTextColor)
        }
        if let changeKind, !node.isDirectory {
            return changeKind.tintColor
        }
        return .primary
    }
}

private struct FileTreeDirectoryContents: View {
    let parentURL: URL
    let children: [FileNode]
    @Bindable var model: FileTreeModel
    @Binding var selectedFileURL: URL?
    let projectRootURL: URL?
    let gitStatusSnapshot: GitWorkingTreeStatusSnapshot?
    let onCreateItem: (FileTreeCreationKind) -> Void
    let onCommitCreation: () -> Void

    var body: some View {
        let directories = children.filter { $0.isDirectory }
        let files = children.filter { !$0.isDirectory }
        let pendingCreation = model.pendingCreation(forParent: parentURL)

        Group {
            if let pendingCreation, pendingCreation.kind == .folder {
                let insertionIndex = model.insertionIndex(for: pendingCreation, among: directories)
                childRows(Array(directories.prefix(insertionIndex)))
                PendingCreationRow(
                    model: model,
                    creation: pendingCreation,
                    onCommitCreation: onCommitCreation
                )
                childRows(Array(directories.suffix(from: insertionIndex)))
                childRows(files)
            } else if let pendingCreation, pendingCreation.kind == .file {
                childRows(directories)
                let insertionIndex = model.insertionIndex(for: pendingCreation, among: files)
                childRows(Array(files.prefix(insertionIndex)))
                PendingCreationRow(
                    model: model,
                    creation: pendingCreation,
                    onCommitCreation: onCommitCreation
                )
                childRows(Array(files.suffix(from: insertionIndex)))
            } else {
                childRows(children)
            }
        }
    }

    @ViewBuilder
    private func childRows(_ nodes: [FileNode]) -> some View {
        FileTreeRows(
            nodes: nodes,
            model: model,
            selectedFileURL: $selectedFileURL,
            projectRootURL: projectRootURL,
            gitStatusSnapshot: gitStatusSnapshot,
            onCreateItem: onCreateItem,
            onCommitCreation: onCommitCreation
        )
    }
}

private struct FileTreeNodeIcon: View {
    let node: FileNode
    let changeKind: GitWorkingTreeChangeKind?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: node.iconName)
                .foregroundStyle(node.iconColor)

            if let changeKind {
                Image(systemName: changeKind.overlaySymbolName)
                    .font(.system(size: 9, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, changeKind.tintColor)
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 18, height: 16)
    }
}

private struct PendingCreationRow: View {
    @Bindable var model: FileTreeModel
    let creation: PendingFileTreeCreation
    let onCommitCreation: () -> Void

    @FocusState private var isFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: creation.kind == .folder ? "folder.fill" : "doc")
                    .foregroundStyle(creation.kind == .folder ? Color.blue : Color.secondary)

                TextField(creation.kind.placeholder, text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(onCommitCreation)
            }

            if let validationMessage = model.pendingCreation?.validationMessage {
                Text(validationMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 2)
        .id(creation.id)
        .onAppear {
            installKeyMonitor()
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { model.pendingCreation?.name ?? creation.name },
            set: { model.updatePendingCreationName($0) }
        )
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isFocused, event.window?.isKeyWindow == true else { return event }
            switch event.keyCode {
            case 53:
                model.cancelPendingCreation()
                return nil
            case 76:
                onCommitCreation()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
