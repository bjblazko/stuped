import AppKit

final class MiniMapView: NSView {
    static let width: CGFloat = 80

    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    private var isPaused = false

    override var isFlipped: Bool { true }

    func setup(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        needsDisplay = true
    }

    @objc func contentChanged() {
        guard !isPaused else { return }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // 1. Background
        ctx.setFillColor(textView.backgroundColor.cgColor)
        ctx.fill(bounds)

        // 2. Left separator
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 0.25, y: 0))
        ctx.addLine(to: CGPoint(x: 0.25, y: bounds.height))
        ctx.strokePath()

        guard !isPaused else { return }

        let string = textView.string as NSString
        let totalTextHeight = max(textView.frame.height, 1)

        guard string.length > 0 else {
            drawViewportRect(ctx, totalTextHeight: totalTextHeight,
                             slotHeight: 2.5, logicalLineCount: 0, isDark: isDark)
            return
        }

        // Pre-count logical lines so we can compute a zoom-to-fit slot height.
        // Counting '\n' is O(n) but cheap — no layout needed.
        var logicalLineCount = 1
        let nsStr = textView.string as NSString
        var pos = 0
        while pos < nsStr.length {
            let ch = nsStr.character(at: pos)
            if ch == unichar(10) { logicalLineCount += 1 }  // '\n'
            pos += 1
        }
        logicalLineCount = min(logicalLineCount, 5000)

        // Scale slot height so all lines fit within the mini-map height.
        let maxSlotHeight: CGFloat = 2.5
        let slotHeight = min(maxSlotHeight, bounds.height / CGFloat(logicalLineCount))
        let barHeight = max(0.5, slotHeight * 0.6)

        // 3. Line bars with syntax-highlighted segments
        layoutManager.ensureLayout(for: textContainer)
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)

        // Pass 1: find the widest logical line (usedRect is in layout coords, not
        // container-size coords, so this works correctly for both word-wrap modes —
        // including when containerSize.width == CGFloat.greatestFiniteMagnitude).
        var maxLineWidth: CGFloat = 1
        layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) {
            (_, usedRect, _, glyphRange, _) in
            let charRange = layoutManager.characterRange(
                forGlyphRange: glyphRange, actualGlyphRange: nil)
            let isStart = charRange.location == 0
                || string.character(at: charRange.location - 1) == unichar(10)
            if isStart { maxLineWidth = max(maxLineWidth, usedRect.width) }
        }

        let containerWidth = maxLineWidth
        let usableWidth = bounds.width - 4  // 2pt padding each side

        let defaultBarColor: CGColor = isDark
            ? NSColor.white.withAlphaComponent(0.45).cgColor
            : NSColor.black.withAlphaComponent(0.35).cgColor

        let textStorage = textView.textStorage
        var lineIndex: CGFloat = 0

        layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) {
            (_, usedRect, _, glyphRange, stop) in

            if lineIndex >= CGFloat(logicalLineCount) {
                stop.pointee = true
                return
            }

            let charRange = layoutManager.characterRange(
                forGlyphRange: glyphRange, actualGlyphRange: nil)

            // Only draw for the first fragment of each logical line
            let isLogicalLineStart = charRange.location == 0
                || string.character(at: charRange.location - 1) == unichar(("\n" as UnicodeScalar).value)
            guard isLogicalLineStart else { return }

            let y = lineIndex * slotHeight
            let lineWidth = usedRect.width / containerWidth
            let totalBarWidth = max(2, lineWidth * usableWidth)

            // Draw colored segments per attribute run (syntax highlighting)
            if let storage = textStorage, charRange.length > 0 {
                storage.enumerateAttributes(in: charRange, options: []) { attrs, runRange, _ in
                    let runStart = runRange.location - charRange.location
                    let xFraction = CGFloat(runStart) / CGFloat(charRange.length)
                    let widthFraction = CGFloat(runRange.length) / CGFloat(charRange.length)
                    let x = 2 + xFraction * totalBarWidth
                    let w = max(0.5, widthFraction * totalBarWidth)

                    if let color = attrs[.foregroundColor] as? NSColor {
                        ctx.setFillColor(color.withAlphaComponent(0.75).cgColor)
                    } else {
                        ctx.setFillColor(defaultBarColor)
                    }
                    ctx.fill(CGRect(x: x, y: y, width: w, height: barHeight))
                }
            } else {
                ctx.setFillColor(defaultBarColor)
                ctx.fill(CGRect(x: 2, y: y, width: totalBarWidth, height: barHeight))
            }

            lineIndex += 1
        }

        // 4. Selection overlay — tint lines that are within the current text selection
        let selectedRanges = textView.selectedRanges
            .compactMap { $0 as? NSValue }
            .map { $0.rangeValue }
            .filter { $0.length > 0 }

        if !selectedRanges.isEmpty {
            let selColor = NSColor.selectedTextBackgroundColor
                .withAlphaComponent(isDark ? 0.45 : 0.35).cgColor
            var selLineIndex: CGFloat = 0

            layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) {
                (_, _, _, glyphRange, stop) in
                if selLineIndex >= CGFloat(logicalLineCount) {
                    stop.pointee = true; return
                }
                let charRange = layoutManager.characterRange(
                    forGlyphRange: glyphRange, actualGlyphRange: nil)
                let isStart = charRange.location == 0
                    || string.character(at: charRange.location - 1) == unichar(10)
                guard isStart else { return }

                for sel in selectedRanges {
                    if NSIntersectionRange(charRange, sel).length > 0 {
                        let y = selLineIndex * slotHeight
                        ctx.setFillColor(selColor)
                        ctx.fill(CGRect(x: 0, y: y,
                                        width: self.bounds.width,
                                        height: max(slotHeight, 0.5)))
                        break
                    }
                }
                selLineIndex += 1
            }
        }

        // 5. Viewport overlay — uses the same slotHeight so it aligns with bars
        drawViewportRect(ctx, totalTextHeight: totalTextHeight,
                         slotHeight: slotHeight, logicalLineCount: logicalLineCount, isDark: isDark)
    }

    private func drawViewportRect(_ ctx: CGContext, totalTextHeight: CGFloat,
                                  slotHeight: CGFloat, logicalLineCount: Int, isDark: Bool) {
        guard let scrollView = scrollView, totalTextHeight > 0 else { return }

        let clipBounds = scrollView.contentView.bounds
        let scrollY = clipBounds.origin.y
        let visibleH = clipBounds.height

        // Mini-map content height matches exactly what was drawn (all lines fit inside bounds)
        let miniMapContentHeight = CGFloat(logicalLineCount) * slotHeight

        let vpTop = (scrollY / totalTextHeight) * miniMapContentHeight
        let vpHeight = max((visibleH / totalTextHeight) * miniMapContentHeight, slotHeight)

        let vpRect = CGRect(x: 0, y: vpTop, width: bounds.width, height: vpHeight)

        let fillAlpha: CGFloat = isDark ? 0.12 : 0.08
        ctx.setFillColor(NSColor.white.withAlphaComponent(fillAlpha).cgColor)
        ctx.fill(vpRect)

        let strokeAlpha: CGFloat = isDark ? 0.25 : 0.20
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(strokeAlpha).cgColor)
        ctx.setLineWidth(1.0)
        ctx.stroke(vpRect)
    }

    override func mouseDown(with event: NSEvent) {
        scroll(to: event)
    }

    override func mouseDragged(with event: NSEvent) {
        scroll(to: event)
    }

    private func scroll(to event: NSEvent) {
        guard let textView = textView,
              let scrollView = scrollView else { return }

        // Compute the same slot height used during draw() so the coordinate spaces match.
        let logicalLineCount = max(1, textView.string.components(separatedBy: "\n").count)
        let slotHeight = min(2.5, bounds.height / CGFloat(logicalLineCount))
        let miniMapContentHeight = CGFloat(logicalLineCount) * slotHeight

        let y = convert(event.locationInWindow, from: nil).y
        let fraction = max(0, min(y / miniMapContentHeight, 1))
        let totalContent = textView.frame.height
        let visibleHeight = scrollView.contentSize.height
        let targetY = fraction * totalContent
        let clampedY = max(0, min(targetY, totalContent - visibleHeight))

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

extension Notification.Name {
    static let stupedToggleMiniMap = Notification.Name("stupedToggleMiniMap")
    static let stupedToggleWordWrap = Notification.Name("stupedToggleWordWrap")
}
