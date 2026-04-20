import Foundation

enum DocumentViewMode: String, CaseIterable {
    case edit = "Edit"
    case preview = "Preview"
    case split = "Split"

    static func initialMode(for fileURL: URL) -> DocumentViewMode {
        if LanguageMap.isImage(fileURL.pathExtension) {
            return .preview
        }
        if LanguageMap.previewType(for: fileURL.pathExtension) != nil {
            return .split
        }
        return .edit
    }
}

@Observable
final class TabItem: Identifiable {
    let id = UUID()
    let fileURL: URL
    var text: String
    /// The text as it exists on disk — used to compute isDirty.
    var savedText: String
    var viewMode: DocumentViewMode

    var isDirty: Bool { text != savedText }
    var displayName: String { fileURL.lastPathComponent }

    init(fileURL: URL, text: String) {
        self.fileURL = fileURL
        self.text = text
        self.savedText = text
        self.viewMode = DocumentViewMode.initialMode(for: fileURL)
    }

    func markSaved() {
        savedText = text
    }
}
