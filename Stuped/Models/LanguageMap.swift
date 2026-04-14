import Foundation
import UniformTypeIdentifiers

enum PreviewType {
    case markdown
    case html
    case image
}

enum LanguageMap {
    /// Maps a file extension to the highlight.js language identifier.
    static func language(for fileExtension: String) -> String? {
        let ext = fileExtension.lowercased()
        return extensionToLanguage[ext]
    }

    /// Maps a UTType to the highlight.js language identifier.
    static func language(for utType: UTType) -> String? {
        if let ext = utType.preferredFilenameExtension {
            return language(for: ext)
        }
        return nil
    }

    /// Determines if a file extension corresponds to a markdown file.
    static func isMarkdown(_ fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased()
        return markdownExtensions.contains(ext)
    }

    /// Returns the preview type for a file extension, or nil if the file cannot be meaningfully previewed.
    static func previewType(for fileExtension: String) -> PreviewType? {
        let ext = fileExtension.lowercased()
        if markdownExtensions.contains(ext) { return .markdown }
        if htmlExtensions.contains(ext) { return .html }
        if imageExtensions.contains(ext) { return .image }
        return nil
    }

    /// Determines if a file extension supports preview rendering.
    static func isPreviewable(_ fileExtension: String) -> Bool {
        previewType(for: fileExtension) != nil
    }

    /// Determines if a file extension corresponds to an image file.
    static func isImage(_ fileExtension: String) -> Bool {
        imageExtensions.contains(fileExtension.lowercased())
    }

    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdx"
    ]

    private static let htmlExtensions: Set<String> = [
        "html", "htm", "xhtml"
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif",
        "webp", "heic", "heif", "ico", "svg"
    ]

    private static let extensionToLanguage: [String: String] = [
        // Web
        "html": "xml",
        "htm": "xml",
        "xhtml": "xml",
        "xml": "xml",
        "svg": "xml",
        "css": "css",
        "scss": "scss",
        "sass": "scss",
        "less": "less",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "jsx": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "json": "json",
        "graphql": "graphql",
        "gql": "graphql",

        // Systems
        "c": "c",
        "h": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "cxx": "cpp",
        "hpp": "cpp",
        "hxx": "cpp",
        "m": "objectivec",
        "mm": "objectivec",
        "swift": "swift",
        "rs": "rust",
        "go": "go",
        "zig": "zig",

        // JVM
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "scala": "scala",
        "groovy": "groovy",
        "gradle": "groovy",
        "clj": "clojure",

        // .NET
        "cs": "csharp",
        "fs": "fsharp",
        "vb": "vbnet",

        // Scripting
        "py": "python",
        "pyw": "python",
        "rb": "ruby",
        "php": "php",
        "pl": "perl",
        "pm": "perl",
        "lua": "lua",
        "r": "r",
        "R": "r",
        "jl": "julia",
        "ex": "elixir",
        "exs": "elixir",
        "erl": "erlang",
        "hrl": "erlang",
        "hs": "haskell",
        "lhs": "haskell",
        "ml": "ocaml",
        "mli": "ocaml",

        // Shell
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "fish": "bash",
        "ps1": "powershell",
        "psm1": "powershell",
        "bat": "dos",
        "cmd": "dos",

        // Config / Data
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "ini",
        "ini": "ini",
        "cfg": "ini",
        "conf": "nginx",
        "properties": "properties",
        "env": "bash",

        // Markup / Docs
        "md": "markdown",
        "markdown": "markdown",
        "mdown": "markdown",
        "mkd": "markdown",
        "tex": "latex",
        "latex": "latex",
        "rst": "plaintext",

        // Database
        "sql": "sql",

        // Build / DevOps
        "dockerfile": "dockerfile",
        "docker": "dockerfile",
        "makefile": "makefile",
        "mk": "makefile",
        "cmake": "cmake",
        "tf": "hcl",
        "hcl": "hcl",
        "nix": "nix",

        // Other
        "diff": "diff",
        "patch": "diff",
        "proto": "protobuf",
        "wasm": "wasm",
        "wat": "wasm",
        "vim": "vim",
        "el": "lisp",
        "lisp": "lisp",
        "scm": "scheme",
        "dart": "dart",
        "v": "verilog",
        "vhd": "vhdl",
        "vhdl": "vhdl",
    ]
}
