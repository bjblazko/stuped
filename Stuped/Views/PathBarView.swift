import SwiftUI
import AppKit

struct PathBarView<Trailing: View>: View {
    var fileURL: URL?
    var projectRootURL: URL?
    var gitInfo: GitInfo?
    var onNavigate: ((URL) -> Void)?
    var onShowGitChanges: (() -> Void)?
    private let trailing: Trailing

    /// No trailing content.
    init(fileURL: URL?, projectRootURL: URL? = nil, gitInfo: GitInfo?, onNavigate: ((URL) -> Void)? = nil,
         onShowGitChanges: (() -> Void)? = nil)
        where Trailing == EmptyView
    {
        self.fileURL = fileURL
        self.projectRootURL = projectRootURL
        self.gitInfo = gitInfo
        self.onNavigate = onNavigate
        self.onShowGitChanges = onShowGitChanges
        self.trailing = EmptyView()
    }

    /// With trailing content (e.g. a view-mode picker).
    init(fileURL: URL?, projectRootURL: URL? = nil, gitInfo: GitInfo?, onNavigate: ((URL) -> Void)? = nil,
         onShowGitChanges: (() -> Void)? = nil,
         @ViewBuilder trailing: () -> Trailing)
    {
        self.fileURL = fileURL
        self.projectRootURL = projectRootURL
        self.gitInfo = gitInfo
        self.onNavigate = onNavigate
        self.onShowGitChanges = onShowGitChanges
        self.trailing = trailing()
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Breadcrumbs — scrolls horizontally, takes all remaining space
            if let url = fileURL {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            pathComponents(for: url)
                        }
                        .padding(.horizontal, 12)
                    }
                    .onAppear {
                        proxy.scrollTo("last", anchor: .trailing)
                    }
                    .onChange(of: fileURL) { _, _ in
                        proxy.scrollTo("last", anchor: .trailing)
                    }
                }
            } else {
                Spacer(minLength: 0)
            }

            // Git branch badge
            if let branch = gitInfo?.branchName {
                if let onShowGitChanges {
                    Button(action: onShowGitChanges) {
                        branchBadge(branch)
                    }
                    .buttonStyle(.plain)
                    .help(gitInfo?.remoteURL ?? "No remote configured")
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                } else {
                    branchBadge(branch)
                        .help(gitInfo?.remoteURL ?? "No remote configured")
                }
            }

            // Trailing slot (e.g. view-mode picker)
            trailing
        }
        .padding(.vertical, 4)
        .padding(.trailing, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func branchBadge(_ branch: String) -> some View {
        HStack(spacing: 4) {
            Divider().frame(height: 12)

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(branch)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func pathComponents(for url: URL) -> some View {
        let components = url.pathComponents.filter { $0 != "/" }
        ForEach(Array(components.enumerated()), id: \.offset) { index, component in
            if index > 0 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 2)
            }

            let isLast = index == components.count - 1
            let targetURL = targetURL(componentIndex: index, fullURL: url)
            Button {
                onNavigate?(targetURL)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isLast ? fileIcon(for: url) : "folder")
                        .font(.system(size: 10))
                    Text(component)
                        .font(.system(size: 11))
                }
                .foregroundStyle(isLast ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .id(isLast ? "last" : "c\(index)")
            .contextMenu {
                CopyPathMenu(url: targetURL, projectRootURL: projectRootURL)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }

    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if LanguageMap.isMarkdown(ext) { return "doc.richtext" }
        if ["html", "htm", "xhtml"].contains(ext) { return "globe" }
        if LanguageMap.isImage(ext) { return "photo" }
        return "doc"
    }

    private func buildPath(componentIndex: Int, fullURL: URL) -> String {
        let components = fullURL.pathComponents // ["/", "Users", "name", ...]
        let actualIndex = componentIndex + 1 // skip the "/" root element
        guard actualIndex < components.count else { return "/" }

        var path = "/"
        for i in 1...actualIndex {
            path += components[i]
            if i < actualIndex { path += "/" }
        }
        return path
    }

    private func targetURL(componentIndex: Int, fullURL: URL) -> URL {
        let path = buildPath(componentIndex: componentIndex, fullURL: fullURL)
        return URL(fileURLWithPath: path)
    }
}
