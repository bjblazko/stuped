import SwiftUI
import AppKit

private enum SearchMode: String, CaseIterable {
    case filename = "Filename"
    case contents = "Contents"
    case both     = "Both"
}

private struct GlobalSearchMatch: Identifiable, Equatable {
    let id         = UUID()
    let url        : URL
    let lineNumber : Int?    // nil → file-name match
    let lineText   : String? // nil → file-name match
}

/// Content view for the Find-in-Files panel (hosted inside GlobalSearchWindowManager's NSPanel).
/// The window itself provides chrome, background, shadow, and native resize handles.
struct GlobalSearchPopupView: View {
    let rootURL  : URL
    let onClose  : () -> Void
    let onSelect : (URL) -> Void

    @AppStorage("fileTree.showHiddenFiles") private var showHiddenFiles = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText     = ""
    @State private var searchMode     : SearchMode = .both
    @State private var extFilter      = ""
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
        VStack(spacing: 0) {
            searchBar
            Divider()
            // The Group is always stretched to fill the panel's remaining space.
            // Without this, the view's ideal height collapses to ~100 px in the
            // empty/no-results states, which NSHostingView relays to AppKit and
            // causes the NSPanel to shrink itself to that compact size.
            Group {
                if searchText.isEmpty {
                    emptyLabel("Type to search")
                } else if isSearching && matches.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(20)
                } else if matches.isEmpty {
                    emptyLabel("No results")
                } else {
                    VSplitView {
                        resultsList
                            .frame(minHeight: 80)
                        previewPanel
                            .frame(minHeight: 60)
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
        .onChange(of: searchMode)   { _, _ in selectedIdx = 0 }
        .onChange(of: extFilter)    { _, _ in selectedIdx = 0 }
        .onChange(of: effectiveIdx) { _, _ in updatePreview() }
        // Re-focus search field when results arrive — guards against any layout-driven
        // focus loss that might occur when the body switches from emptyLabel to VSplitView.
        .onChange(of: matches)      { _, _ in searchFocused = true }
        // Include rootURL.path so the search reruns when the user switches projects.
        .task(id: searchText + searchMode.rawValue + extFilter + rootURL.path) {
            await performSearch()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Search files…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)

            // Extension filter
            HStack(spacing: 3) {
                Text("ext:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("", text: $extFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 52)
            }

            // Mode popup button (macOS-native)
            Picker("", selection: $searchMode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Results list

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // VStack (not LazyVStack): LazyVStack mis-reports its viewport inside
                // VSplitView, causing isSelected props to not update for visible rows.
                // With ≤50 results the performance difference is negligible.
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { idx, m in
                        MatchRowView(
                            match: m,
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
            .onChange(of: matches) { _, _ in
                proxy.scrollTo(effectiveIdx, anchor: .top)
            }
        }
    }

    // MARK: - Preview panel

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if previewLines.isEmpty {
                Text("No preview")
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
            }
        }
    }

    private func emptyLabel(_ label: String) -> some View {
        Text(label)
            .foregroundStyle(.secondary)
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(20)
    }

    // MARK: - Key monitor
    // "Find in Files" window title guard prevents this monitor from consuming arrow
    // keys when the panel is hidden (not key) and the user is in the main editor.

    private func installKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.title == "Find in Files" else { return event }
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

    // MARK: - Navigation

    private func move(by delta: Int) {
        guard !matches.isEmpty else { return }
        selectedIdx = (effectiveIdx + delta + matches.count) % matches.count
    }

    private func confirm() {
        guard !matches.isEmpty else { return }
        onSelect(matches[effectiveIdx].url)
        onClose()
    }

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
        let start = max(0, lineNum - 5)
        let end   = min(lines.count - 1, lineNum + 3)
        previewLines = (start...end).map { i in (i + 1, lines[i]) }
    }

    // MARK: - Search

    private func performSearch() async {
        let q      = searchText
        let mode   = searchMode
        let extRaw = extFilter
        let root   = rootURL          // capture current project root by value
        guard !q.isEmpty else { matches = []; isSearching = false; return }
        isSearching = true
        let includeHidden = showHiddenFiles

        let found: [GlobalSearchMatch] = await Task.detached(priority: .userInitiated) {
            var hits: [GlobalSearchMatch] = []
            let lower  = q.lowercased()
            let extReq = extRaw.isEmpty ? nil
                : (extRaw.hasPrefix(".") ? String(extRaw.dropFirst()) : extRaw).lowercased()

            for url in allFiles(under: root, includeHidden: includeHidden) {
                if Task.isCancelled || hits.count >= 50 { break }

                if let ext = extReq, url.pathExtension.lowercased() != ext { continue }

                let nameLower = url.lastPathComponent.lowercased()
                let nameMatch = nameLower.contains(lower)

                switch mode {
                case .filename:
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
        .background(isSelected ? Color.accentColor.opacity(0.20) : .clear)
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
