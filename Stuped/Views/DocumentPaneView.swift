import SwiftUI

struct DocumentPaneView: View {
    @Binding var text: String
    let fileURL: URL?
    let projectRootURL: URL?
    @Binding var viewMode: DocumentViewMode
    let wordWrap: Bool
    let showMiniMap: Bool
    let isActive: Bool
    let onNavigate: (URL) -> Void
    let onShowGitChanges: (() -> Void)?

    @State private var editorState = EditorState()
    @State private var gitInfo: GitInfo?
    @State private var editorScrollPosition: CGPoint = .zero
    @State private var previewScrollPosition: CGPoint = .zero

    private var previewType: PreviewType? {
        guard let url = fileURL else { return nil }
        return LanguageMap.previewType(for: url.pathExtension)
    }

    private var isPreviewable: Bool { previewType != nil }
    private var isImageFile: Bool { previewType == .image }
    private var detectedLanguage: String? {
        guard let fileURL else { return nil }
        return LanguageMap.language(for: fileURL.pathExtension)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isActive {
                PathBarView(
                    fileURL: fileURL,
                    projectRootURL: projectRootURL,
                    gitInfo: gitInfo,
                    onNavigate: onNavigate,
                    onShowGitChanges: onShowGitChanges
                ) {
                    if isPreviewable && !isImageFile {
                        viewModePicker
                    }
                }
            }

            editorArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isActive && viewMode != .preview && !isImageFile {
                StatusBarView(editorState: editorState, language: detectedLanguage)
            }
        }
        .onAppear {
            normalizeViewMode()
            if isActive {
                synchronizeEditorState()
                refreshGitInfo()
            }
        }
        .onChange(of: fileURL) { _, _ in
            normalizeViewMode()
            if isActive || fileURL == nil {
                refreshGitInfo()
            }
        }
        .onChange(of: text) { _, _ in
            if isActive {
                synchronizeEditorState()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                synchronizeEditorState()
                refreshGitInfo()
            }
        }
    }

    @ViewBuilder
    private var editorArea: some View {
        if isImageFile {
            if let url = fileURL {
                ImagePreviewView(fileURL: url)
            } else {
                ContentUnavailableView("No File Selected", systemImage: "photo")
            }
        } else {
            switch viewMode {
            case .edit:
                CodeEditorView(
                    text: $text,
                    language: detectedLanguage,
                    editorState: editorState,
                    isActive: isActive,
                    wordWrap: wordWrap,
                    showMiniMap: showMiniMap,
                    scrollPosition: editorScrollPosition,
                    onScrollPositionChanged: { editorScrollPosition = $0 }
                )
            case .preview:
                previewView
            case .split:
                HSplitView {
                    CodeEditorView(
                        text: $text,
                        language: detectedLanguage,
                        editorState: editorState,
                        isActive: isActive,
                        wordWrap: wordWrap,
                        showMiniMap: showMiniMap,
                        scrollPosition: editorScrollPosition,
                        onScrollPositionChanged: { editorScrollPosition = $0 }
                    )
                    .frame(minWidth: 250)

                    previewView
                        .frame(minWidth: 250)
                }
            }
        }
    }

    @ViewBuilder
    private var previewView: some View {
        if let previewType {
            switch previewType {
            case .markdown, .html:
                MarkdownPreviewView(
                    text: text,
                    previewType: previewType,
                    fileURL: fileURL,
                    isActive: isActive,
                    scrollPosition: previewScrollPosition,
                    onScrollPositionChanged: { previewScrollPosition = $0 }
                )
            case .image:
                if let url = fileURL {
                    ImagePreviewView(fileURL: url)
                } else {
                    ContentUnavailableView("No File Selected", systemImage: "photo")
                }
            }
        } else {
            Text("Preview not available for this file type.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var viewModePicker: some View {
        HStack(spacing: 0) {
            Divider().frame(height: 12)
            Picker("View Mode", selection: $viewMode) {
                Image(systemName: "doc.plaintext").tag(DocumentViewMode.edit)
                Image(systemName: "rectangle.split.2x1").tag(DocumentViewMode.split)
                Image(systemName: "eye").tag(DocumentViewMode.preview)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 108)
            .padding(.leading, 8)
        }
    }

    private func normalizeViewMode() {
        if isImageFile {
            viewMode = .preview
        } else if !isPreviewable && viewMode != .edit {
            viewMode = .edit
        }
    }

    private func synchronizeEditorState() {
        editorState.detectLineEnding(in: text)
        editorState.detectIndentation(in: text)
    }

    private func refreshGitInfo() {
        guard let fileURL else {
            gitInfo = nil
            return
        }

        Task {
            let info = await GitInfo.fetch(for: fileURL)
            await MainActor.run {
                gitInfo = info
            }
        }
    }
}
