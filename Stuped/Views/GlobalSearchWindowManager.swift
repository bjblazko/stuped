import AppKit
import SwiftUI

/// Manages the singleton "Find in Files" panel window.
/// Using a real NSPanel gives native resize handles, proper window management,
/// and stable focus — none of which are achievable with a SwiftUI overlay.
final class GlobalSearchWindowManager: NSObject {
    static let shared = GlobalSearchWindowManager()

    private static let autosaveName        = "GlobalSearchPanel5"
    private static let defaultContentSize  = NSSize(width: 720, height: 640)
    private static let minimumContentSize  = NSSize(width: 620, height: 420)

    private var panel: NSPanel?

    private override init() {}

    // MARK: - Public API

    func toggle(rootURL: URL, onSelect: @escaping (URL) -> Void) {
        if let p = panel, p.isVisible {
            p.orderOut(nil)
        } else {
            open(rootURL: rootURL, onSelect: onSelect)
        }
    }

    func open(rootURL: URL, onSelect: @escaping (URL) -> Void) {
        let p = panel ?? makePanel()
        panel = p

        let content = GlobalSearchPopupView(
            rootURL: rootURL,
            onClose: { [weak p] in p?.orderOut(nil) },
            onSelect: onSelect
        )
        // Fresh NSHostingController each open so onAppear / key monitor fires correctly.
        // sizingOptions = [] stops SwiftUI from updating preferredContentSize on the
        // panel. Combined with .frame(maxHeight: .infinity) in GlobalSearchPopupView,
        // the hosting view reports "fill available space" as its ideal size, so
        // AppKit never receives a signal to shrink the panel.
        let hc = NSHostingController(rootView: content)
        hc.sizingOptions = []
        p.contentViewController = hc

        // Apply frame BEFORE makeKeyAndOrderFront so the panel appears at the right
        // size immediately. With sizingOptions = [] nothing will override this.
        if !p.isVisible {
            let restored = p.setFrameUsingName(Self.autosaveName)
            if !restored || !p.hasUsableContentSize(Self.minimumContentSize) {
                p.setFrame(
                    p.frameRect(forContentRect: NSRect(origin: .zero, size: Self.defaultContentSize)),
                    display: false
                )
                p.center()
            }
            if p.frameAutosaveName.isEmpty {
                p.setFrameAutosaveName(Self.autosaveName)
            }
        }

        p.makeKeyAndOrderFront(nil)

        // Focus must be deferred: makeFirstResponder only works once the window is key.
        DispatchQueue.main.async { [weak p] in
            guard let panel = p else { return }
            if let tf = Self.firstTextField(in: panel.contentView) {
                panel.makeFirstResponder(tf)
            }
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask:   [.titled, .closable, .resizable],
            backing:     .buffered,
            defer:       false
        )
        p.title = "Find in Files"
        p.isReleasedWhenClosed = false
        p.contentMinSize = Self.minimumContentSize
        return p
    }

    /// Depth-first search for the first editable NSTextField in a view hierarchy.
    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable { return tf }
        for sub in view.subviews {
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - NSWindow helpers

private extension NSWindow {
    func hasUsableContentSize(_ minimumContentSize: NSSize) -> Bool {
        let contentSize = contentRect(forFrameRect: frame).size
        return contentSize.width >= minimumContentSize.width
            && contentSize.height >= minimumContentSize.height
    }
}
