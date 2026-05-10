import SwiftUI
import AppKit

private struct FileSearchMatch: Identifiable, Equatable {
    let id   = UUID()
    let url  : URL
}

/// Content view for the "Find File" (Open Quickly) panel.
struct FileSearchPopupView: View {
    let rootURL  : URL
    let onClose  : () -> Void
    let onSelect : (URL) -> Void

    @AppStorage("fileTree.showHiddenFiles") private var showHiddenFiles = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText     = ""
    @State private var matches        : [FileSearchMatch] = []
    @State private var isSearching    = false
    @State private var selectedIdx    = 0
    @State private var previewLines   : [(num: Int, text: String)] = []
    @FocusState private var searchFocused: Bool
    @State private var eventMonitor   : Any?

    private var effectiveIdx: Int {
        matches.isEmpty ? 0 : min(selectedIdx, matches.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            Group {
                if searchText.isEmpty {
                    emptyLabel("Type a filename…")
                } else if isSearching && matches.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(20)
                } else if matches.isEmpty {
                    emptyLabel("No files found")
                } else {
                    VSplitView {
                        resultsList
                            .frame(minHeight: 120)
                        previewPanel
                            .frame(minHeight: 100)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            searchFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: searchText)   { _, _ in selectedIdx = 0 }
        .onChange(of: effectiveIdx) { _, _ in updatePreview() }
        .onChange(of: matches)      { _, _ in searchFocused = true }
        .task(id: searchText + rootURL.path) {
            await performSearch()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Open Quickly…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { idx, m in
                        FileMatchRowView(
                            url: m.url,
                            searchTerm: searchText,
                            isSelected: idx == effectiveIdx,
                            rootURL: rootURL
                        )
                        .id(idx)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(m.url); onClose() }
                    }
                }
            }
            .onChange(of: effectiveIdx) { _, i in
                withAnimation(.easeInOut(duration: 0.08)) { proxy.scrollTo(i, anchor: .center) }
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if previewLines.isEmpty {
                Text("No preview available")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if let m = matches[safe: effectiveIdx] {
                    HStack(spacing: 4) {
                        Text(m.url.lastPathComponent)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(relativeDir(m.url))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    Divider()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(previewLines, id: \.num) { line in
                            HStack(spacing: 0) {
                                Text("\(line.num)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                                    .padding(.trailing, 8)
                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func emptyLabel(_ label: String) -> some View {
        Text(label)
            .foregroundStyle(.secondary)
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(40)
    }

    private func installKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.title == "Open Quickly" else { return event }
            switch event.keyCode {
            case 125: self.move(by:  1); return nil   // ↓
            case 126: self.move(by: -1); return nil   // ↑
            case 36:  self.confirm();    return nil   // Return
            case 53:  self.onClose();    return nil   // Escape
            default:  return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private func move(by delta: Int) {
        guard !matches.isEmpty else { return }
        selectedIdx = (effectiveIdx + delta + matches.count) % matches.count
    }

    private func confirm() {
        guard !matches.isEmpty else { return }
        onSelect(matches[effectiveIdx].url)
        onClose()
    }

    private func updatePreview() {
        guard !matches.isEmpty else { previewLines = []; return }
        let url = matches[effectiveIdx].url
        
        guard let data = try? Data(contentsOf: url) else {
            previewLines = []
            return
        }
        
        // Don't preview binary files
        if data.prefix(min(data.count, 1024)).contains(0x00) {
            previewLines = [(1, "[Binary file]")]
            return
        }
        
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: .newlines)
        let count = min(lines.count, 20)
        previewLines = (0..<count).map { i in (i + 1, lines[i]) }
    }

    private func performSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        let root = rootURL
        guard !q.isEmpty else { matches = []; isSearching = false; return }
        isSearching = true
        let includeHidden = showHiddenFiles

        let found: [FileSearchMatch] = await Task.detached(priority: .userInitiated) {
            var hits: [URL] = []
            let all = allFiles(under: root, includeHidden: includeHidden)
            
            // Build matching logic
            let matcher = FileMatcher(query: q)
            
            for url in all {
                if Task.isCancelled || hits.count >= 100 { break }
                if matcher.matches(url.lastPathComponent) {
                    hits.append(url)
                }
            }
            
            return hits.map { FileSearchMatch(url: $0) }
        }.value

        if !Task.isCancelled {
            matches = found
            isSearching = false
            updatePreview()
        }
    }

    private func relativeDir(_ url: URL) -> String {
        let dir  = url.deletingLastPathComponent().path
        let root = rootURL.path
        if dir == root { return "/" }
        if dir.hasPrefix(root) { return String(dir.dropFirst(root.count)) }
        return dir
    }
}

private struct FileMatcher {
    let query: String
    private let regex: NSRegularExpression?
    private let isFuzzy: Bool

    init(query: String) {
        self.query = query
        
        // If it has wildcards, use regex matching
        if query.contains("*") || query.contains("?") {
            self.isFuzzy = false
            let pattern = "^" + NSRegularExpression.escapedPattern(for: query)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".") + "$"
            self.regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } else {
            // Fuzzy: match characters in order. "mvp" -> "m.*v.*p"
            self.isFuzzy = true
            let chars = query.map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = chars.joined(separator: ".*")
            
            // If query has uppercase, make it case-sensitive
            let hasUpper = query.contains { $0.isUppercase }
            self.regex = try? NSRegularExpression(
                pattern: pattern,
                options: hasUpper ? [] : [.caseInsensitive]
            )
        }
    }

    func matches(_ filename: String) -> Bool {
        guard let regex = regex else { return false }
        let range = NSRange(filename.startIndex..., in: filename)
        return regex.firstMatch(in: filename, options: [], range: range) != nil
    }
}

private struct FileMatchRowView: View {
    let url       : URL
    let searchTerm: String
    let isSelected: Bool
    let rootURL   : URL

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                Text(relDir)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.20) : .clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(width: 3)
            }
        }
    }

    private var fileIcon: NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 16, height: 16)
        return img
    }

    private var relDir: String {
        let dir  = url.deletingLastPathComponent().path
        let root = rootURL.path
        if dir == root { return "/" }
        if dir.hasPrefix(root) { return String(dir.dropFirst(root.count)) }
        return dir
    }
}

private func allFiles(under root: URL, includeHidden: Bool) -> [URL] {
    let opts: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
    guard let e = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: opts
    ) else { return [] }
    return (e.allObjects as? [URL] ?? []).filter {
        ((try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false) == false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
