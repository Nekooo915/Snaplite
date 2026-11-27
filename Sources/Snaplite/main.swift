import AppKit
import SnapliteCore

@MainActor
final class MinimalAppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let capturer = Capturer()
    private let hotkeys = HotkeyManager()
    private var showObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = hotkeys.register(preferences.hotkey) { [weak self] in
            guard let self else { return }
            self.capturer.capture(using: self.preferences)
        }
        showObserver = SingleInstance.observeShowRequests {}
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.cleanup()
        if let showObserver {
            DistributedNotificationCenter.default().removeObserver(showObserver)
        }
    }
}

if SingleInstance.tryForwardToExisting() {
    exit(0)
}

let app = NSApplication.shared
let delegate = MinimalAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
