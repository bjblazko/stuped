import Foundation
import SwiftUI
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
        if isDirectory { return "folder.fill" }
        switch fileExtension {
        case "swift":                                    return "swift"
        case "html", "htm", "xhtml":                    return "globe"
        case "css", "scss", "sass", "less":             return "paintpalette"
        case "json":                                     return "curlybraces"
        case "xml", "plist", "svg":                     return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown", "mdown", "mkd", "mdx":  return "doc.richtext"
        case "sh", "bash", "zsh", "fish":               return "terminal"
        case "yml", "yaml", "toml", "ini", "cfg",
             "conf", "env", "properties":               return "gearshape"
        case "png", "jpg", "jpeg", "gif",
             "webp", "heic", "ico", "bmp", "tiff":      return "photo"
        case "pdf":                                      return "doc.fill"
        case "zip", "tar", "gz", "bz2", "7z", "rar":   return "archivebox"
        case "sql":                                      return "cylinder"
        case "dockerfile", "docker":                     return "shippingbox"
        default:                                         return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return .blue }
        switch fileExtension {
        // Red
        case "swift", "rs":
            return .red
        // Orange
        case "py", "pyw", "html", "htm", "xhtml", "java":
            return .orange
        // Yellow
        case "js", "mjs", "cjs", "jsx", "ts", "tsx", "json":
            return .yellow
        // Green
        case "go", "sh", "bash", "zsh", "fish", "bat", "cmd",
             "ps1", "psm1":
            return .green
        // Mint
        case "md", "markdown", "mdown", "mkd", "mdx",
             "rst", "tex", "latex":
            return .mint
        // Teal
        case "css", "scss", "sass", "less":
            return .teal
        // Cyan
        case "xml", "plist", "yml", "yaml", "toml",
             "ini", "cfg", "conf", "env", "properties":
            return .cyan
        // Blue
        case "c", "h", "cpp", "cc", "cxx", "hpp", "hxx":
            return .blue
        // Indigo
        case "kt", "kts", "scala", "groovy", "gradle",
             "clj", "erl", "hrl":
            return .indigo
        // Purple
        case "rb", "php", "pl", "pm", "lua",
             "ex", "exs", "hs", "lhs", "ml", "mli",
             "lisp", "el", "scm":
            return .purple
        // Pink
        case "png", "jpg", "jpeg", "gif", "svg",
             "webp", "heic", "ico", "bmp", "tiff", "tif":
            return .pink
        // Red (secondary)
        case "sql":
            return Color(red: 0.9, green: 0.3, blue: 0.3)
        // Orange (secondary)
        case "dockerfile", "docker", "makefile", "mk", "cmake":
            return .orange
        // Secondary for everything else
        default:
            return .secondary
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
