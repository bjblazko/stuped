import AppKit
import SwiftUI

/// Manages the singleton "Git Changes" panel window.
final class GitChangesWindowManager: NSObject {
    static let shared = GitChangesWindowManager()

    private static let autosaveName = "GitChangesPanel1"
    private static let defaultSize = NSSize(width: 620, height: 460)
    private static let minAcceptableHeight: CGFloat = 280

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
            let frameIsUsable = panel.frame.height >= Self.minAcceptableHeight
            if !restored || !frameIsUsable {
                var frame = panel.frame
                frame.size = NSSize(
                    width: Self.defaultSize.width,
                    height: Self.defaultSize.height + panel.titleBarHeight
                )
                panel.setFrame(frame, display: false)
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
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Git Changes"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 240)
        return panel
    }
}

private extension NSWindow {
    var titleBarHeight: CGFloat {
        frame.height - contentRect(forFrameRect: frame).height
    }
}
