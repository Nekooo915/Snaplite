import AppKit
import SnapliteCore
import SwiftUI

/// Manages the lazy on-demand SwiftUI Settings window.
/// Allocates `NSHostingController` and `SettingsViewModel` only on `show()`,
/// and destroys the entire SwiftUI graph immediately on close.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let hotkeyManager: HotkeyManager
    private let permissionOverride: Bool?
    private let appearanceOverride: NSAppearance?
    private let onRegisterHotkey: @MainActor (HotkeyBinding) -> Result<Void, HotkeyError>
    private let onOpenFolder: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void

    private var window: NSWindow?
    private var viewModel: SettingsViewModel?

    init(
        preferences: Preferences,
        hotkeyManager: HotkeyManager,
        permissionOverride: Bool? = nil,
        appearanceOverride: NSAppearance? = nil,
        onRegisterHotkey: @escaping @MainActor (HotkeyBinding) -> Result<Void, HotkeyError>,
        onOpenFolder: @escaping @MainActor () -> Void,
        onQuit: @escaping @MainActor () -> Void
    ) {
        self.preferences = preferences
        self.hotkeyManager = hotkeyManager
        self.permissionOverride = permissionOverride
        self.appearanceOverride = appearanceOverride
        self.onRegisterHotkey = onRegisterHotkey
        self.onOpenFolder = onOpenFolder
        self.onQuit = onQuit
        super.init()
    }

    func show() {
        if let existing = window {
            viewModel?.refreshSystemState()
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let vm = SettingsViewModel(
            preferences: preferences,
            hotkeyManager: hotkeyManager,
            permissionOverride: permissionOverride,
            onRegisterHotkey: onRegisterHotkey,
            onOpenFolder: onOpenFolder,
            onQuit: onQuit
        )

        let hostingController = NSHostingController(rootView: SettingsView(viewModel: vm))
        hostingController.sizingOptions = [.preferredContentSize]

        let fittingSize = hostingController.sizeThatFits(
            in: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        )
        let initialSize = NSSize(
            width: 400,
            height: max(260, ceil(fittingSize.height))
        )

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = Strings.current().appTitle
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.moveToActiveSpace]
        if let appearanceOverride {
            win.appearance = appearanceOverride
        }
        win.contentViewController = hostingController
        win.setContentSize(initialSize)
        win.delegate = self

        vm.hostWindow = win
        self.viewModel = vm
        self.window = win

        positionWindowOnActiveScreen(win)
        NSApp.activate()
        win.orderFrontRegardless()
        win.makeKeyAndOrderFront(nil)
    }

    func refreshIfVisible() {
        guard window != nil else { return }
        viewModel?.refreshSystemState()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        if viewModel?.isRecordingHotkey == true {
            viewModel?.stopRecordingHotkey()
        }
    }

    func windowWillClose(_ notification: Notification) {
        viewModel?.cleanupOnWindowClose()
        viewModel?.hostWindow = nil
        if let closingWindow = window {
            closingWindow.delegate = nil
            closingWindow.contentViewController = nil
        }
        window = nil
        viewModel = nil
    }

    // MARK: - Positioning

    private func positionWindowOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        let frame = window.frame
        let x = round(visible.midX - frame.width / 2)
        let y = round(visible.minY + (visible.height - frame.height) * 0.56)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
