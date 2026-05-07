import AppKit
import SwiftUI

/// Owns the single settings NSWindow. We don't use SwiftUI's app-level
/// `WindowGroup` because we want fine-grained control over close/reopen
/// behaviour (the close button hides instead of destroying the window
/// so re-showing it is instant).
final class SettingsWindowController {
    private var window: NSWindow?
    private weak var state: AppState?
    // NSWindow holds its delegate weakly, so we own the proxy strongly
    // here — otherwise it deallocates immediately, the window loses its
    // delegate, and `windowShouldClose` never fires (which is exactly
    // what made the Dock icon get stuck after closing).
    private var delegateProxy: WindowDelegateProxy?

    /// Called on the main thread after the user dismisses the panel. The
    /// AppDelegate hooks this to restore the Dock-icon visibility implied
    /// by the current config — otherwise the brief `.regular` activation
    /// done while showing the window would leave the Dock icon stranded.
    var onClose: (() -> Void)?

    init(state: AppState) {
        self.state = state
    }

    /// Create the window if it doesn't exist yet, then bring it forward.
    /// Mirrors the macOS reopen / Dock-icon-click flow used by AppDelegate.
    func showWindow() {
        guard let state else { return }

        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: SettingsView(state: state))
        let win = NSWindow(contentViewController: host)
        win.title = "Snaplite"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.minSize = NSSize(width: 420, height: 480)
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("SnapliteSettings")

        let proxy = WindowDelegateProxy()
        proxy.onClose = { [weak self] in
            self?.window?.orderOut(nil)
            self?.onClose?()
        }
        win.delegate = proxy
        self.delegateProxy = proxy

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide the window without destroying it. Caller signals "user dismissed
    /// the panel"; we keep state around so re-opening is cheap.
    func hideWindow() {
        window?.orderOut(nil)
    }

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }
}

/// Bridges NSWindowDelegate events back to a closure. AppDelegate wires
/// the "user clicked close" event to "hide, don't destroy".
private final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return false  // we hide ourselves, don't let AppKit destroy the window
    }
}
