import AppKit
import SwiftUI

/// Manages the singleton "Find in Files" panel window.
/// Using a real NSPanel gives native resize handles, proper window management,
/// and stable focus — none of which are achievable with a SwiftUI overlay.
final class GlobalSearchWindowManager: NSObject {
    static let shared = GlobalSearchWindowManager()

    private static let autosaveName = "GlobalSearchPanel4"
    private static let defaultSize  = NSSize(width: 720, height: 640)
    private static let minAcceptableHeight: CGFloat = 400

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
        // sizingOptions = [] prevents SwiftUI from resizing the panel to its compact
        // ideal size after we explicitly set the frame in the deferred block below.
        let hc = NSHostingController(rootView: content)
        hc.sizingOptions = []
        p.contentViewController = hc

        let wasVisible = p.isVisible
        p.makeKeyAndOrderFront(nil)

        // Defer size + focus correction to the next run-loop pass so it fires
        // after SwiftUI's layout has settled (which can shrink the window back
        // to the view's compact ideal size, overriding setContentSize calls
        // made synchronously before or right after makeKeyAndOrderFront).
        DispatchQueue.main.async { [weak p] in
            guard let panel = p else { return }

            if !wasVisible {
                // Try to restore user's saved position/size. If none exists yet,
                // or if the saved frame has a suspiciously small height (e.g. from
                // a previous session where NSPanel collapsed to SwiftUI's compact
                // ideal size before autosave), apply the default size and centre.
                let restored = panel.setFrameUsingName(Self.autosaveName)
                let frameIsUsable = panel.frame.height >= Self.minAcceptableHeight
                if !restored || !frameIsUsable {
                    var r = panel.frame
                    r.size = NSSize(
                        width:  Self.defaultSize.width,
                        height: Self.defaultSize.height + panel.titleBarHeight
                    )
                    panel.setFrame(r, display: false)
                    panel.center()
                }
                if panel.frameAutosaveName.isEmpty {
                    panel.setFrameAutosaveName(Self.autosaveName)
                }
            }

            // Directly focus the search field — more reliable than @FocusState
            // which needs the window to already be key when it fires.
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
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask:   [.titled, .closable, .resizable],
            backing:     .buffered,
            defer:       false
        )
        p.title = "Find in Files"
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 420, height: 300)
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
    /// Height of the title bar in points.
    var titleBarHeight: CGFloat {
        frame.height - contentRect(forFrameRect: frame).height
    }
}
