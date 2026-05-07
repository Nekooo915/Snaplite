import AppKit

/// Toggles the Dock icon by switching `NSApplication.activationPolicy`
/// between `.regular` (Dock visible, full app behaviour) and `.accessory`
/// (no Dock icon, menubar-style background app). Matches the Rust build.
enum DockIcon {
    static func setVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        if visible {
            // When transitioning back to .regular, make sure the user
            // actually sees a window.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
