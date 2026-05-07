import AppKit

// If another instance is already running, forward "show" to it and exit
// before NSApp ever boots. Mirrors the Rust build's startup gate.
if SingleInstance.tryForwardToExisting() {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Start as a menubar-only app; AppDelegate flips this to .regular while a
// window is open if the user hid the tray icon.
app.setActivationPolicy(.accessory)
app.run()
