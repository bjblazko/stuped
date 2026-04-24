import AppKit

final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    var gutterWidth: CGFloat = 44
    private var isPaused = false

    override var isFlipped: Bool { true }

    func setup(textView: NSTextView) {
        self.textView = textView

        NotificationCenter.default.addObserver(
            self, selector: #selector(needsRedraw),
            name: NSText.didChangeNotification, object: textView
        )
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(needsRedraw),
                name: NSView.boundsDidChangeNotification, object: clipView
            )
        }
    }

    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        needsDisplay = true
    }

    @objc private func needsRedraw() {
        guard !isPaused else { return }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }

        // Background
        textView.backgroundColor.setFill()
        bounds.fill()

        // Separator
        NSColor.separatorColor.setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        sep.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        sep.lineWidth = 0.5
        sep.stroke()

        guard !isPaused else { return }

        let string = textView.string as NSString
        guard string.length > 0 else { return }

        let font = NSFont.monospacedDigitSystemFont(
            ofSize: (textView.font?.pointSize ?? 13) - 1, weight: .regular
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let visibleRect = scrollView.contentView.bounds
        let insetY = textView.textContainerInset.height

        // Ensure layout
        layoutManager.ensureLayout(for: textContainer)

        // Track which lines we've already drawn (by line number)
        var lineNumber = 1
        var lastCharIdx = 0

        // Enumerate all line fragments
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) {
            (fragmentRect, _, _, glyphRange, _) in

            let charRange = layoutManager.characterRange(
                forGlyphRange: glyphRange, actualGlyphRange: nil
            )

            // Count newlines we skipped (for lines that share a fragment)
            while lastCharIdx < charRange.location {
                let lineRange = string.lineRange(for: NSRange(location: lastCharIdx, length: 0))
                lastCharIdx = NSMaxRange(lineRange)
                if lastCharIdx <= charRange.location {
                    lineNumber += 1
                }
            }

            // Y position in gutter coordinates
            let yPos = fragmentRect.origin.y + insetY - visibleRect.origin.y

            // Only draw if visible
            if yPos + fragmentRect.height >= 0 && yPos <= self.bounds.height {
                let numStr = "\(lineNumber)" as NSString
                let size = numStr.size(withAttributes: attrs)
                let point = NSPoint(
                    x: self.gutterWidth - size.width - 8,
                    y: yPos + (fragmentRect.height - size.height) / 2
                )
                numStr.draw(at: point, withAttributes: attrs)
            }

            lastCharIdx = NSMaxRange(charRange)
            lineNumber += 1
        }

        // Extra line fragment for trailing newline
        let extraRect = layoutManager.extraLineFragmentRect
        if extraRect.height > 0 {
            let yPos = extraRect.origin.y + insetY - visibleRect.origin.y
            if yPos + extraRect.height >= 0 && yPos <= bounds.height {
                let numStr = "\(lineNumber)" as NSString
                let size = numStr.size(withAttributes: attrs)
                let point = NSPoint(
                    x: gutterWidth - size.width - 8,
                    y: yPos + (extraRect.height - size.height) / 2
                )
                numStr.draw(at: point, withAttributes: attrs)
            }
        }
    }
}
