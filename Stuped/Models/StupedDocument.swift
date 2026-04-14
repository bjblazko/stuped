import SwiftUI
import UniformTypeIdentifiers

struct StupedDocument: FileDocument {
    var text: String
    var fileURL: URL?

    static var readableContentTypes: [UTType] = [
        .plainText,
        .sourceCode,
        .json,
        .xml,
        .yaml,
        .html,
        .shellScript,
        .data,
    ]

    static var writableContentTypes: [UTType] = [
        .plainText,
        .sourceCode,
        .json,
        .xml,
        .yaml,
        .html,
        .shellScript,
    ]

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Check for binary content (null bytes in first 8KB)
        let checkLength = min(data.count, 8192)
        let prefix = data.prefix(checkLength)
        if prefix.contains(0x00) {
            self.text = ""
            return
        }

        self.text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }

    var fileExtension: String {
        fileURL?.pathExtension ?? ""
    }

    var isMarkdown: Bool {
        LanguageMap.isMarkdown(fileExtension)
    }

    var previewType: PreviewType? {
        LanguageMap.previewType(for: fileExtension)
    }

    var isPreviewable: Bool {
        previewType != nil
    }

    var detectedLanguage: String? {
        LanguageMap.language(for: fileExtension)
    }

    var isBinary: Bool {
        text.isEmpty && fileURL != nil
    }
}
