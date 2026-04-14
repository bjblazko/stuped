import SwiftUI

struct StatusBarView: View {
    var editorState: EditorState
    var language: String?

    var body: some View {
        HStack(spacing: 16) {
            // Cursor position
            Text("Ln \(editorState.cursorLine), Col \(editorState.cursorColumn)")

            Divider().frame(height: 12)

            // Line count
            Text("\(editorState.lineCount) lines")

            Spacer()

            // Language
            if let lang = language {
                Text(lang.capitalized)
                Divider().frame(height: 12)
            }

            // Indentation
            if let indent = editorState.indentStyle {
                Text(indent)
                Divider().frame(height: 12)
            }

            // Line ending
            Text(editorState.lineEnding)

            Divider().frame(height: 12)

            // Encoding
            Text(editorState.encoding)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
