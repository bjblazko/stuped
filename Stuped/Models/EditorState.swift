import Foundation
import Observation

@Observable
class EditorState {
    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    var lineCount: Int = 1
    var encoding: String = "UTF-8"
    var lineEnding: String = "LF"
    var indentStyle: String? = nil  // nil = not detected / not applicable

    func detectLineEnding(in text: String) {
        if text.contains("\r\n") {
            lineEnding = "CRLF"
        } else if text.contains("\r") {
            lineEnding = "CR"
        } else {
            lineEnding = "LF"
        }
    }

    func detectIndentation(in text: String) {
        var tabCount = 0
        var spaceCount = 0
        var spaceWidths: [Int: Int] = [:]  // width -> count

        for line in text.components(separatedBy: "\n").prefix(200) {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("\t") {
                tabCount += 1
            } else if line.hasPrefix(" ") {
                spaceCount += 1
                let leading = line.prefix(while: { $0 == " " }).count
                if leading >= 2 {
                    spaceWidths[leading, default: 0] += 1
                }
            }
        }

        if tabCount == 0 && spaceCount == 0 {
            indentStyle = nil
            return
        }

        if tabCount > spaceCount {
            indentStyle = "Tabs"
        } else {
            // Find most common indent width (2 or 4 typically)
            let width = spaceWidths.max(by: { a, b in a.value < b.value })?.key ?? 4
            // Normalize: if we see lots of 8-space indents but also 4, prefer 4
            let likely = [2, 4].min(by: { abs($0 - width) < abs($1 - width) }) ?? width
            indentStyle = "Spaces: \(likely)"
        }
    }

    func updateCursor(text: String, selectedRange: NSRange) {
        let nsString = text as NSString
        lineCount = text.components(separatedBy: "\n").count

        // Calculate line and column from character offset
        let location = min(selectedRange.location, nsString.length)
        let textUpToCursor = nsString.substring(to: location)
        let lines = textUpToCursor.components(separatedBy: "\n")
        cursorLine = lines.count
        cursorColumn = (lines.last?.count ?? 0) + 1
    }
}
