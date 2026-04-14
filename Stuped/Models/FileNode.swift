import Foundation
import UniformTypeIdentifiers

struct FileNode: Identifiable, Hashable {
    let id: URL
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var isMarkdown: Bool {
        LanguageMap.isMarkdown(fileExtension)
    }

    var iconName: String {
        if isDirectory {
            return "folder.fill"
        }

        switch fileExtension {
        case "swift":
            return "swift"
        case "py":
            return "text.page"
        case "js", "jsx", "ts", "tsx":
            return "text.page"
        case "html", "htm":
            return "globe"
        case "css", "scss", "less":
            return "paintpalette"
        case "json":
            return "curlybraces"
        case "xml", "plist":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown":
            return "doc.richtext"
        case "sh", "bash", "zsh":
            return "terminal"
        case "yml", "yaml", "toml", "ini", "cfg", "conf":
            return "gearshape"
        case "png", "jpg", "jpeg", "gif", "svg", "ico", "webp":
            return "photo"
        case "pdf":
            return "doc.fill"
        case "zip", "tar", "gz", "bz2", "7z", "rar":
            return "archivebox"
        case "c", "h", "cpp", "cc", "cxx", "hpp":
            return "text.page"
        case "rs":
            return "text.page"
        case "go":
            return "text.page"
        case "java", "kt", "kts":
            return "text.page"
        case "rb":
            return "text.page"
        case "sql":
            return "cylinder"
        default:
            return "doc"
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.url == rhs.url
    }
}
