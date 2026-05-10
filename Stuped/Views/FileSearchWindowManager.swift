import AppKit
import SwiftUI

/// Manages the singleton "Open Quickly" panel window.
final class FileSearchWindowManager: NSObject {
    static let shared = FileSearchWindowManager()

    private static let autosaveName        = "FileSearchPanel1"
    private static let defaultContentSize  = NSSize(width: 600, height: 500)
    private static let minimumContentSize  = NSSize(width: 500, height: 350)

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

        let content = FileSearchPopupView(
            rootURL: rootURL,
            onClose: { [weak p] in p?.orderOut(nil) },
            onSelect: onSelect
        )
        
        let hc = NSHostingController(rootView: content)
        hc.sizingOptions = []
        p.contentViewController = hc

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
        p.title = "Open Quickly"
        p.isReleasedWhenClosed = false
        p.contentMinSize = Self.minimumContentSize
        return p
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable { return tf }
        for sub in view.subviews {
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }
}

private extension NSWindow {
    func hasUsableContentSize(_ minimumContentSize: NSSize) -> Bool {
        let contentSize = contentRect(forFrameRect: frame).size
        return contentSize.width >= minimumContentSize.width
            && contentSize.height >= minimumContentSize.height
    }
}
