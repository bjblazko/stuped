import AppKit
import SwiftUI

// Replaces the zoom button's action with fullscreen once the view lands in a window.
private final class ZoomInterceptorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            window.collectionBehavior.insert(.fullScreenPrimary)
            guard let btn = window.standardWindowButton(.zoomButton) else { return }
            btn.target = window
            btn.action = #selector(NSWindow.toggleFullScreen(_:))
        }
    }
}

private struct ZoomInterceptorRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> ZoomInterceptorView { ZoomInterceptorView() }
    func updateNSView(_ nsView: ZoomInterceptorView, context: Context) {}
}

extension View {
    /// Redirects the green zoom button to enter fullscreen instead of zooming.
    func fullScreenOnZoom() -> some View {
        background(ZoomInterceptorRepresentable().frame(width: 0, height: 0))
    }
}
