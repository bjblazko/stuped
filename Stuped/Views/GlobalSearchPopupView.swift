import SwiftUI
import AppKit

private enum SearchMode: String, CaseIterable {
    case name     = "Name"
    case contents = "Contents"
    case both     = "Both"
}

private struct GlobalSearchMatch: Identifiable {
    let id         = UUID()
    let url        : URL
    let lineNumber : Int?    // nil → file-name match
    let lineText   : String? // nil → file-name match
}

/// Floating "Find in Files" popup triggered by Cmd+Shift+F in folder mode.
/// Shows one row per matching line (content) or per matching file (name),
/// with a file-content preview panel below the results.
struct GlobalSearchPopupView: View {
    let rootURL  : URL
    @Binding var isShowing: Bool
    let onSelect : (URL) -> Void

    @AppStorage("fileTree.showHiddenFiles") private var showHiddenFiles = false

    @State private var searchText     = ""
    @State private var searchMode     : SearchMode = .contents
    @State private var matches        : [GlobalSearchMatch] = []
    @State private var isSearching    = false
    @State private var selectedIdx    = 0
    @State private var previewLines   : [(num: Int, text: String)] = []
    @State private var selectedLineNum: Int? = nil
    @FocusState private var searchFocused: Bool
    @State private var eventMonitor   : Any?

    private var effectiveIdx: Int {
        matches.isEmpty ? 0 : min(selectedIdx, matches.count - 1)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { closePopup() }

            popupCard
                .frame(width: 540)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            searchFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: searchText) { _, _ in selectedIdx = 0 }
        .onChange(of: searchMode) { _, _ in selectedIdx = 0 }
        .onChange(of: effectiveIdx) { _, _ in updatePreview() }
        .task(id: searchText + searchMode.rawValue) {
            await performSearch()
        }
    }

    // MARK: - Popup card

    private var popupCard: some View {
        VStack(spacing: 0) {
            searchBar
            modePicker
            Divider()
            if searchText.isEmpty {
                emptyLabel("Type to search")
            } else if isSearching && matches.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(20)
            } else if matches.isEmpty {
                emptyLabel("No results")
            } else {
                resultsList
                if !previewLines.isEmpty {
                    Divider()
                    previewPanel
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField("Search files…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var modePicker: some View {
        Picker("", selection: $searchMode) {
            ForEach(SearchMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { idx, m in
                        MatchRowView(
                            match: m,
                            searchTerm: searchText,
                            isSelected: idx == effectiveIdx,
                            rootURL: rootURL
                        )
                        .id(idx)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(m.url); closePopup() }
                    }
                }
            }
            .frame(maxHeight: 210)
            .onChange(of: effectiveIdx) { _, i in
                withAnimation(.easeInOut(duration: 0.08)) { proxy.scrollTo(i, anchor: .center) }
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: filename + relative path
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
            // Line listing
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(previewLines, id: \.num) { line in
                        HStack(spacing: 0) {
                            Text("\(line.num)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .frame(width: 42, alignment: .trailing)
                                .padding(.trailing, 10)
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                        .background(line.num == selectedLineNum
                            ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 145)
        }
    }

    private func emptyLabel(_ label: String) -> some View {
        Text(label)
            .foregroundStyle(.secondary)
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(20)
    }

    // MARK: - Key monitor (reliable arrow-key capture on macOS)

    private func installKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 125: self.move(by:  1); return nil   // ↓
            case 126: self.move(by: -1); return nil   // ↑
            case 36:  self.confirm();    return nil   // Return
            case 53:  self.closePopup(); return nil   // Escape
            default:  return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - Navigation

    private func move(by delta: Int) {
        guard !matches.isEmpty else { return }
        selectedIdx = (effectiveIdx + delta + matches.count) % matches.count
    }

    private func confirm() {
        guard !matches.isEmpty else { return }
        onSelect(matches[effectiveIdx].url)
        closePopup()
    }

    private func closePopup() { isShowing = false }

    // MARK: - Preview update

    private func updatePreview() {
        guard !matches.isEmpty else { previewLines = []; return }
        let m = matches[effectiveIdx]
        guard let lineNum = m.lineNumber else {
            previewLines = []
            selectedLineNum = nil
            return
        }
        selectedLineNum = lineNum
        guard let data = try? Data(contentsOf: m.url),
              let text = String(data: data, encoding: .utf8) else {
            previewLines = []
            return
        }
        let lines = text.components(separatedBy: .newlines)
        let start = max(0, lineNum - 5)        // 0-indexed
        let end   = min(lines.count - 1, lineNum + 3)
        previewLines = (start...end).map { i in (i + 1, lines[i]) }
    }

    // MARK: - Search

    private func performSearch() async {
        let q    = searchText
        let mode = searchMode
        guard !q.isEmpty else { matches = []; isSearching = false; return }
        isSearching = true
        let includeHidden = showHiddenFiles

        let found: [GlobalSearchMatch] = await Task.detached(priority: .userInitiated) {
            var hits: [GlobalSearchMatch] = []
            let lower = q.lowercased()

            for url in allFiles(under: rootURL, includeHidden: includeHidden) {
                if Task.isCancelled || hits.count >= 50 { break }
                let nameLower  = url.lastPathComponent.lowercased()
                let nameMatch  = nameLower.contains(lower)

                switch mode {
                case .name:
                    if nameMatch {
                        hits.append(GlobalSearchMatch(url: url, lineNumber: nil, lineText: nil))
                    }
                case .contents:
                    for (ln, lt) in (contentMatches(in: url, lower: lower) ?? []).prefix(5) {
                        if hits.count >= 50 { break }
                        hits.append(GlobalSearchMatch(url: url, lineNumber: ln, lineText: lt))
                    }
                case .both:
                    if nameMatch {
                        hits.append(GlobalSearchMatch(url: url, lineNumber: nil, lineText: nil))
                    } else {
                        for (ln, lt) in (contentMatches(in: url, lower: lower) ?? []).prefix(5) {
                            if hits.count >= 50 { break }
                            hits.append(GlobalSearchMatch(url: url, lineNumber: ln, lineText: lt))
                        }
                    }
                }
            }
            return hits
        }.value

        if !Task.isCancelled {
            matches = found
            isSearching = false
            updatePreview()
        }
    }

    // MARK: - Path helper

    private func relativeDir(_ url: URL) -> String {
        let dir  = url.deletingLastPathComponent().path
        let root = rootURL.path
        if dir == root { return "" }
        if dir.hasPrefix(root) { return String(dir.dropFirst(root.count)) }
        return dir
    }
}

// MARK: - File helpers (file-private)

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

private func contentMatches(in url: URL, lower: String) -> [(Int, String)]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    if data.prefix(min(data.count, 8192)).contains(0x00) { return nil }
    var results: [(Int, String)] = []
    for (i, line) in String(decoding: data, as: UTF8.self)
        .components(separatedBy: .newlines).enumerated()
    {
        if line.lowercased().contains(lower) {
            results.append((i + 1, line.trimmingCharacters(in: .whitespaces)))
        }
    }
    return results.isEmpty ? nil : results
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Match row

private struct MatchRowView: View {
    let match     : GlobalSearchMatch
    let searchTerm: String
    let isSelected: Bool
    let rootURL   : URL

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: 14, height: 14)

            Group {
                if let lt = match.lineText {
                    highlighted(lt, term: searchTerm)
                        .font(.system(size: 12, design: .monospaced))
                } else {
                    highlighted(match.url.lastPathComponent, term: searchTerm)
                        .font(.system(size: 12))
                }
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            if let ln = match.lineNumber {
                Text("\(match.url.lastPathComponent):\(ln)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(relDir)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(width: 2)
            }
        }
    }

    private var fileIcon: NSImage {
        let img = NSWorkspace.shared.icon(forFile: match.url.path)
        img.size = NSSize(width: 14, height: 14)
        return img
    }

    private var relDir: String {
        let dir  = match.url.deletingLastPathComponent().path
        let root = rootURL.path
        if dir == root { return "/" }
        if dir.hasPrefix(root) { return String(dir.dropFirst(root.count)) }
        return dir
    }

    /// Renders `text` with the first occurrence of `term` in orange+bold.
    @ViewBuilder
    private func highlighted(_ text: String, term: String) -> some View {
        let lower     = text.lowercased()
        let termLower = term.lowercased()
        if let range = lower.range(of: termLower) {
            let before  = String(text[..<range.lowerBound])
            let matched = String(text[range])
            let after   = String(text[range.upperBound...])
            (Text(before)
             + Text(matched).bold().foregroundColor(.orange)
             + Text(after))
        } else {
            Text(text)
        }
    }
}
