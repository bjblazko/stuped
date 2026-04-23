import AppKit
import SwiftUI

/// Manages the singleton "Git Changes" panel window.
final class GitChangesWindowManager: NSObject {
    static let shared = GitChangesWindowManager()

    private static let autosaveName = "GitChangesPanel1"
    private static let defaultContentSize = NSSize(width: 620, height: 460)
    private static let minimumContentSize = NSSize(width: 560, height: 340)

    private var panel: NSPanel?

    private override init() {}

    func open(snapshot: GitWorkingTreeStatusSnapshot, onSelect: @escaping (GitChangedFile) -> Void) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let content = GitChangesPopupView(
            snapshot: snapshot,
            onClose: { [weak panel] in panel?.orderOut(nil) },
            onSelect: onSelect
        )

        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = []
        panel.contentViewController = hostingController

        if !panel.isVisible {
            let restored = panel.setFrameUsingName(Self.autosaveName)
            if !restored || !panel.hasUsableContentSize(Self.minimumContentSize) {
                panel.setFrame(
                    panel.frameRect(forContentRect: NSRect(origin: .zero, size: Self.defaultContentSize)),
                    display: false
                )
                panel.center()
            }
            if panel.frameAutosaveName.isEmpty {
                panel.setFrameAutosaveName(Self.autosaveName)
            }
        }

        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Git Changes"
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = Self.minimumContentSize
        return panel
    }
}

private extension NSWindow {
    func hasUsableContentSize(_ minimumContentSize: NSSize) -> Bool {
        let contentSize = contentRect(forFrameRect: frame).size
        return contentSize.width >= minimumContentSize.width
            && contentSize.height >= minimumContentSize.height
    }
}
