import AppKit
import CoreGraphics

/// Screen Recording permission checks and System Settings helpers.
public enum Permission {
    /// Returns `true` when macOS has granted Screen Recording access to this process.
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the macOS Screen Recording permission prompt (or registers the app in System Settings).
    @discardableResult
    public static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Opens System Settings directly to Privacy & Security → Screen & System Audio Recording.
    @MainActor
    public static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Spawns a detached shell helper to reopen the current `.app` bundle after a short delay,
    /// then terminates the running instance so newly granted TCC permissions take effect.
    @MainActor
    public static func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.4; open \"$1\"", "_", bundlePath]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        NSApp.terminate(nil)
    }
}
