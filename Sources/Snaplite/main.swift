import AppKit
import SnapliteCore

if SingleInstance.tryForwardToExisting() {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
