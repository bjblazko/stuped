import Foundation

@Observable
final class TabItem: Identifiable {
    let id = UUID()
    let fileURL: URL
    var text: String
    /// The text as it exists on disk — used to compute isDirty.
    var savedText: String

    var isDirty: Bool { text != savedText }
    var displayName: String { fileURL.lastPathComponent }

    init(fileURL: URL, text: String) {
        self.fileURL = fileURL
        self.text = text
        self.savedText = text
    }

    func markSaved() {
        savedText = text
    }
}
