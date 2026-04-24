import SwiftUI
import AppKit
import Highlighter

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var language: String?
    var fontSize: CGFloat = 13
    var editorState: EditorState?
    var isActive: Bool = true
    var wordWrap: Bool = false
    var showMiniMap: Bool = true
    var scrollPosition: CGPoint = .zero
    var onScrollPositionChanged: ((CGPoint) -> Void)? = nil
    var onFindBarHeightChanged: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        // Gutter (line numbers)
        let gutter = LineNumberGutterView()
        gutter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gutter)
        context.coordinator.gutterView = gutter

        // Scroll view + text view
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        // Mini-map (right side)
        let miniMap = MiniMapView()
        miniMap.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(miniMap)
        context.coordinator.miniMapView = miniMap

        let mmWidthConstraint = miniMap.widthAnchor.constraint(equalToConstant: MiniMapView.width)
        let mmHiddenConstraint = miniMap.widthAnchor.constraint(equalToConstant: 0)
        mmWidthConstraint.isActive = showMiniMap
        mmHiddenConstraint.isActive = !showMiniMap
        context.coordinator.miniMapWidthConstraint = mmWidthConstraint
        context.coordinator.miniMapHiddenConstraint = mmHiddenConstraint
        context.coordinator.currentShowMiniMap = showMiniMap
        miniMap.isHidden = !showMiniMap

        // Layout: gutter on left, mini-map on right, scroll view fills rest
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: container.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: gutter.gutterWidth),

            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: miniMap.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            miniMap.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            miniMap.topAnchor.constraint(equalTo: container.topAnchor),
            miniMap.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = NSSize(width: 4, height: 8)
        Self.applyEditorColors(to: textView, scrollView: scrollView)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        textView.defaultParagraphStyle = paragraphStyle

        textView.string = text

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Initialize editor state
        editorState?.detectLineEnding(in: text)
        editorState?.detectIndentation(in: text)
        editorState?.updateCursor(text: text, selectedRange: textView.selectedRange())

        // Wire up gutter and mini-map to text view
        gutter.setup(textView: textView)
        let castScrollView = scrollView as! NSScrollView
        miniMap.setup(textView: textView, scrollView: castScrollView)
        gutter.setPaused(!isActive)
        miniMap.setPaused(!isActive || !showMiniMap)

        // Defer highlighting
        DispatchQueue.main.async {
            context.coordinator.setupHighlighter()
            context.coordinator.restoreScrollPosition()
            context.coordinator.updateFocus()
        }

        // Watch dark/light mode; also track find bar visibility via KVO
        let coordinator = context.coordinator
        coordinator.scrollView = castScrollView
        castScrollView.contentView.postsBoundsChangedNotifications = true
        coordinator.scrollObservation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: castScrollView.contentView,
            queue: .main
        ) { [weak coordinator] _ in
            coordinator?.reportScrollPosition()
        }
        coordinator.appearanceObservation = textView.observe(\.effectiveAppearance) { _, _ in
            coordinator.applyHighlighting()
        }
        coordinator.findBarObservation = castScrollView.observe(\.isFindBarVisible, options: [.new]) { [weak coordinator] sv, _ in
            let height: CGFloat = sv.isFindBarVisible ? (sv.findBarView?.frame.height ?? 0) : 0
            DispatchQueue.main.async {
                coordinator?.parent.onFindBarHeightChanged?(height)
            }
        }

        return container
    }

    func updateNSView(_ containerView: NSView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        if context.coordinator.isUpdatingFromTextView { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.scheduleHighlightingIfActive()
        }

        if context.coordinator.currentLanguage != language {
            context.coordinator.currentLanguage = language
            context.coordinator.scheduleHighlightingIfActive()
        }

        if context.coordinator.currentWordWrap != wordWrap,
           let scrollView = textView.enclosingScrollView {
            context.coordinator.currentWordWrap = wordWrap
            Self.applyWordWrap(wordWrap, to: textView, scrollView: scrollView)
        }

        if context.coordinator.currentShowMiniMap != showMiniMap {
            context.coordinator.currentShowMiniMap = showMiniMap
            context.coordinator.miniMapView?.isHidden = !showMiniMap
            context.coordinator.miniMapHiddenConstraint?.isActive = !showMiniMap
            context.coordinator.miniMapWidthConstraint?.isActive = showMiniMap
            context.coordinator.refreshAuxiliaryViewState()
        }

        if let scrollView = textView.enclosingScrollView {
            Self.applyEditorColors(to: textView, scrollView: scrollView)
        }

        textView.isEditable = isActive

        if context.coordinator.currentIsActive != isActive {
            context.coordinator.currentIsActive = isActive
            context.coordinator.refreshAuxiliaryViewState()
            context.coordinator.updateFocus()
            context.coordinator.applyDeferredHighlightingIfNeeded()
        }

        if isActive {
            context.coordinator.restoreScrollPositionIfNeeded()
        }
    }

    private static func applyEditorColors(to textView: NSTextView, scrollView: NSScrollView) {
        let isDark = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let backgroundColor: NSColor = isDark ? .black : .textBackgroundColor
        textView.backgroundColor = backgroundColor
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor
        textView.insertionPointColor = isDark ? .white : .black
    }

    private static func applyWordWrap(_ wrap: Bool, to textView: NSTextView, scrollView: NSScrollView) {
        let contentWidth = scrollView.contentSize.width
        if wrap {
            textView.isHorizontallyResizable = false
            textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            scrollView.hasHorizontalScroller = false
        } else {
            scrollView.hasHorizontalScroller = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: NSTextView?
        weak var gutterView: LineNumberGutterView?
        weak var miniMapView: MiniMapView?
        var isUpdatingFromTextView = false
        var currentLanguage: String?
        var currentWordWrap: Bool = true
        var currentShowMiniMap: Bool = true
        var currentIsActive: Bool
        var miniMapWidthConstraint: NSLayoutConstraint?
        var miniMapHiddenConstraint: NSLayoutConstraint?
        var appearanceObservation: NSKeyValueObservation?
        var findBarObservation: NSKeyValueObservation?
        var scrollObservation: NSObjectProtocol?
        weak var scrollView: NSScrollView?
        private var highlighter: Highlighter?
        private var highlightWorkItem: DispatchWorkItem?
        private var lastRestoredScrollPosition: CGPoint?
        private var needsDeferredHighlighting = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
            self.currentLanguage = parent.language
            self.currentWordWrap = parent.wordWrap
            self.currentShowMiniMap = parent.showMiniMap
            self.currentIsActive = parent.isActive
        }

        deinit {
            appearanceObservation?.invalidate()
            findBarObservation?.invalidate()
            if let scrollObservation {
                NotificationCenter.default.removeObserver(scrollObservation)
            }
        }

        func setupHighlighter() {
            highlighter = Highlighter()
            refreshAuxiliaryViewState()
            scheduleHighlightingIfActive()
        }

        func refreshAuxiliaryViewState() {
            gutterView?.setPaused(!currentIsActive)
            miniMapView?.setPaused(!currentIsActive || !currentShowMiniMap)
        }

        func reportScrollPosition() {
            guard currentIsActive, let scrollView else { return }
            let position = scrollView.contentView.bounds.origin
            lastRestoredScrollPosition = position
            parent.onScrollPositionChanged?(position)
        }

        func restoreScrollPositionIfNeeded() {
            guard currentIsActive else { return }
            guard lastRestoredScrollPosition != parent.scrollPosition else { return }
            restoreScrollPosition()
        }

        func restoreScrollPosition() {
            guard currentIsActive, let scrollView else { return }
            let documentBounds = scrollView.documentView?.bounds ?? .zero
            let maxX = max(0, documentBounds.width - scrollView.contentSize.width)
            let maxY = max(0, documentBounds.height - scrollView.contentSize.height)
            let clampedPosition = CGPoint(
                x: min(max(parent.scrollPosition.x, 0), maxX),
                y: min(max(parent.scrollPosition.y, 0), maxY)
            )
            scrollView.contentView.scroll(to: clampedPosition)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            lastRestoredScrollPosition = clampedPosition
            parent.onScrollPositionChanged?(clampedPosition)
        }

        func updateFocus() {
            guard let textView else { return }

            if currentIsActive {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.currentIsActive,
                          let textView = self.textView,
                          let window = textView.window,
                          window.firstResponder !== textView else { return }
                    window.makeFirstResponder(textView)
                }
            } else if let window = textView.window, window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
        }

        func scheduleHighlightingIfActive() {
            guard currentIsActive else {
                highlightWorkItem?.cancel()
                needsDeferredHighlighting = true
                return
            }
            needsDeferredHighlighting = false
            applyHighlighting()
        }

        func applyDeferredHighlightingIfNeeded() {
            guard currentIsActive, needsDeferredHighlighting else { return }
            needsDeferredHighlighting = false
            applyHighlighting()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                let string = textView.string as NSString
                let selectedRange = textView.selectedRange()
                let lineRange = string.lineRange(for: NSRange(location: selectedRange.location, length: 0))
                let lineText = string.substring(with: lineRange)
                let spacesToRemove = min(lineText.prefix(while: { $0 == " " }).count, 4)
                if spacesToRemove > 0 {
                    let removeRange = NSRange(location: lineRange.location, length: spacesToRemove)
                    if textView.shouldChangeText(in: removeRange, replacementString: "") {
                        textView.replaceCharacters(in: removeRange, with: "")
                        textView.didChangeText()
                    }
                }
                return true
            }
            return false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard currentIsActive, let textView = notification.object as? NSTextView else { return }
            parent.editorState?.updateCursor(text: textView.string, selectedRange: textView.selectedRange())
            miniMapView?.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isUpdatingFromTextView = true
            parent.text = textView.string
            isUpdatingFromTextView = false

            parent.editorState?.updateCursor(text: textView.string, selectedRange: textView.selectedRange())
            miniMapView?.needsDisplay = true

            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.scheduleHighlightingIfActive()
            }
            highlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }

        func applyHighlighting() {
            guard currentIsActive else {
                needsDeferredHighlighting = true
                return
            }
            guard let textView = textView,
                  let highlighter = highlighter else { return }

            if let scrollView = scrollView {
                CodeEditorView.applyEditorColors(to: textView, scrollView: scrollView)
            }

            let code = textView.string
            guard !code.isEmpty, code.utf8.count < 1_000_000 else { return }

            let appearance = textView.effectiveAppearance
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            highlighter.setTheme(isDark ? "atom-one-dark" : "atom-one-light")

            let highlighted: NSAttributedString?
            if let lang = currentLanguage {
                highlighted = highlighter.highlight(code, as: lang)
            } else {
                highlighted = highlighter.highlight(code)
            }

            guard let result = highlighted else { return }

            let mutable = NSMutableAttributedString(attributedString: result)
            let fullRange = NSRange(location: 0, length: mutable.length)
            let font = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            mutable.addAttribute(.font, value: font, range: fullRange)

            if let ps = textView.defaultParagraphStyle {
                mutable.addAttribute(.paragraphStyle, value: ps, range: fullRange)
            }

            let selectedRanges = textView.selectedRanges
            let visibleRect = textView.enclosingScrollView?.contentView.bounds

            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(mutable)
            textView.textStorage?.endEditing()
            miniMapView?.needsDisplay = true

            if let first = selectedRanges.first as? NSValue,
               first.rangeValue.location + first.rangeValue.length <= (textView.string as NSString).length {
                textView.selectedRanges = selectedRanges
            }
            if let rect = visibleRect {
                textView.enclosingScrollView?.contentView.scrollToVisible(rect)
            }
            reportScrollPosition()
        }
    }
}
