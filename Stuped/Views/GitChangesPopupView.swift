import AppKit
import SwiftUI

struct GitChangesPopupView: View {
    let snapshot: GitWorkingTreeStatusSnapshot
    let onClose: () -> Void
    let onSelect: (GitChangedFile) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if snapshot.isClean {
                ContentUnavailableView(
                    "Working Tree Clean",
                    systemImage: "checkmark.circle",
                    description: Text("No new, modified, or deleted files were found.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(GitWorkingTreeChangeKind.allCases, id: \.self) { kind in
                        let files = snapshot.changes(for: kind)
                        if !files.isEmpty {
                            Section("\(kind.sectionTitle) (\(files.count))") {
                                ForEach(files) { change in
                                    GitChangedFileRow(change: change) {
                                        onSelect(change)
                                        onClose()
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Git Changes")
                    .font(.headline)
                Text(snapshot.repoRoot.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(snapshot.changes.count) changed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct GitChangedFileRow: View {
    let change: GitChangedFile
    let onSelect: () -> Void

    var body: some View {
        Group {
            if change.existsOnDisk {
                Button(action: onSelect) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
                    .opacity(0.75)
            }
        }
        .contentShape(Rectangle())
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: fileSymbolName)
                    .foregroundStyle(.secondary)

                Image(systemName: change.kind.overlaySymbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, change.kind.tintColor)
                    .offset(x: 4, y: 4)
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(change.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(change.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !change.existsOnDisk {
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var fileSymbolName: String {
        let ext = URL(fileURLWithPath: change.relativePath).pathExtension.lowercased()
        if LanguageMap.isMarkdown(ext) { return "doc.richtext" }
        if ["html", "htm", "xhtml"].contains(ext) { return "globe" }
        if LanguageMap.isImage(ext) { return "photo" }
        return "doc"
    }
}
