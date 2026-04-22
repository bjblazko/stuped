import Foundation
import SwiftUI

enum GitWorkingTreeChangeKind: String, CaseIterable, Hashable {
    case new
    case modified
    case deleted

    var sectionTitle: String {
        switch self {
        case .new:
            "New"
        case .modified:
            "Modified"
        case .deleted:
            "Deleted"
        }
    }

    var tintColor: Color {
        switch self {
        case .new:
            .green
        case .modified:
            .orange
        case .deleted:
            .red
        }
    }

    var overlaySymbolName: String {
        switch self {
        case .new:
            "plus.circle.fill"
        case .modified:
            "pencil.circle.fill"
        case .deleted:
            "minus.circle.fill"
        }
    }

    fileprivate var sortOrder: Int {
        switch self {
        case .new:
            0
        case .modified:
            1
        case .deleted:
            2
        }
    }
}

struct GitChangedFile: Identifiable, Hashable {
    let repoRoot: URL
    let relativePath: String
    let kind: GitWorkingTreeChangeKind

    var id: String {
        relativePath
    }

    var url: URL {
        repoRoot
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
    }

    var displayName: String {
        url.lastPathComponent
    }

    var displayPath: String {
        relativePath
    }

    var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

struct GitWorkingTreeStatusSnapshot {
    let repoRoot: URL
    let changes: [GitChangedFile]

    private let changeKindsByURL: [URL: GitWorkingTreeChangeKind]

    init(repoRoot: URL, changes: [GitChangedFile]) {
        let normalizedRoot = repoRoot.standardizedFileURL
        let sortedChanges = changes.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }

        self.repoRoot = normalizedRoot
        self.changes = sortedChanges
        self.changeKindsByURL = Dictionary(uniqueKeysWithValues: sortedChanges.map {
            ($0.url.standardizedFileURL, $0.kind)
        })
    }

    var isClean: Bool {
        changes.isEmpty
    }

    func changeKind(for url: URL) -> GitWorkingTreeChangeKind? {
        changeKindsByURL[url.standardizedFileURL]
    }

    func changes(for kind: GitWorkingTreeChangeKind) -> [GitChangedFile] {
        changes.filter { $0.kind == kind }
    }
}

enum GitWorkingTreeStatus {
    static func fetch(for fileOrDirectoryURL: URL) async -> GitWorkingTreeStatusSnapshot? {
        guard let repoRoot = GitCLI.repositoryRoot(for: fileOrDirectoryURL) else {
            return nil
        }
        return await fetch(inRepoRoot: repoRoot)
    }

    static func fetch(inRepoRoot repoRoot: URL) async -> GitWorkingTreeStatusSnapshot? {
        let normalizedRoot = repoRoot.standardizedFileURL
        guard let output = GitCLI.run(
            ["-c", "core.quotepath=false", "status", "--porcelain=v1", "--untracked-files=all"],
            in: normalizedRoot
        ) else {
            return nil
        }

        let changes = output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseStatusLine(String($0), repoRoot: normalizedRoot) }

        return GitWorkingTreeStatusSnapshot(repoRoot: normalizedRoot, changes: changes)
    }

    private static func parseStatusLine(_ line: String, repoRoot: URL) -> GitChangedFile? {
        guard line.count >= 3 else { return nil }

        if line.hasPrefix("?? ") {
            let relativePath = normalizePath(String(line.dropFirst(3)))
            guard !relativePath.isEmpty else { return nil }
            return GitChangedFile(repoRoot: repoRoot, relativePath: relativePath, kind: .new)
        }

        let status = String(line.prefix(2))
        guard let kind = changeKind(for: status) else { return nil }

        let relativePath = normalizePath(String(line.dropFirst(3)))
        guard !relativePath.isEmpty else { return nil }

        return GitChangedFile(repoRoot: repoRoot, relativePath: relativePath, kind: kind)
    }

    private static func changeKind(for status: String) -> GitWorkingTreeChangeKind? {
        if status.contains("D") {
            return .deleted
        }
        if status.contains("A") {
            return .new
        }
        if status.contains("M") || status.contains("R") || status.contains("C")
            || status.contains("T") || status.contains("U")
        {
            return .modified
        }
        return nil
    }

    private static func normalizePath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespaces)

        if let arrowRange = path.range(of: " -> ", options: .backwards) {
            path = String(path[arrowRange.upperBound...])
        }

        if path.first == "\"", path.last == "\"" {
            return String(path.dropFirst().dropLast())
        }

        return path
    }
}
