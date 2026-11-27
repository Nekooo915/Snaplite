import AppKit
import SnapliteCore

/// Pure AppKit resident application delegate.
/// Keeps the app in `.accessory` mode with zero SwiftUI instantiation until Settings is opened.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let hotkeyManager = HotkeyManager()
    private let capturer = Capturer()
    private var menuBar: MenuBar?
    private var settingsWindow: SettingsWindow?
    private var showObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMinimalMainMenu()
        configureCapturer()
        configurePreferences()
        _ = registerHotkey(preferences.hotkey)
        configureMenuBar()
        observeSystemEvents()
        presentInitialWindowIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Toast.dismiss()
        hotkeyManager.cleanup()
        if let showObserver {
            DistributedNotificationCenter.default().removeObserver(showObserver)
            self.showObserver = nil
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
    }

    // MARK: - Wiring

    private func installMinimalMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: Strings.current().menuQuit,
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            NSMenuItem(
                title: "Close",
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureCapturer() {
        capturer.onPermissionRequired = { [weak self] in
            self?.showSettings()
        }

        capturer.onSuccess = { [weak self] mode, _ in
            guard let self, self.preferences.showToast else { return }
            let strings = Strings.current()
            let message: String = switch mode {
            case .copy: strings.toastCopied
            case .save: strings.toastSaved
            case .both: strings.toastCopiedAndSaved
            }
            Toast.showSuccess(message)
        }

        capturer.onError = { message in
            Toast.showError(message)
        }
    }

    private func configurePreferences() {
        preferences.onTrayVisibilityChange = { [weak self] visible in
            self?.menuBar?.setVisible(visible)
        }

        preferences.onHotkeyChange = { [weak self] binding in
            guard let self, self.hotkeyManager.currentBinding != binding else { return }
            _ = self.registerHotkey(binding)
        }
    }

    private func configureMenuBar() {
        let bar = MenuBar(
            preferences: preferences,
            onCapture: { [weak self] in self?.triggerCapture() },
            onOpenFolder: { [weak self] in self?.openSaveFolder() },
            onOpenSettings: { [weak self] in self?.showSettings() },
            onOpenPermission: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        bar.setVisible(preferences.showTrayIcon)
        menuBar = bar
    }

    private func observeSystemEvents() {
        showObserver = SingleInstance.observeShowRequests { [weak self] in
            self?.showSettings()
        }

        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.settingsWindow?.refreshIfVisible()
            }
        }
    }

    private func presentInitialWindowIfNeeded() {
        let args = CommandLine.arguments
        let forceShow = args.contains("--show-settings")
            || args.contains("--preview-permission")
        let previewToast = args.contains("--preview-toast")

        if let appearance = resolvedAppearanceOverride(from: args) {
            NSApp.appearance = appearance
        }

        if previewToast {
            Toast.showSuccess(Strings.current().toastCopiedAndSaved)
        }

        let needsOnboarding = !preferences.hasCompletedOnboarding
        let missingPermission = !Permission.isGranted

        guard forceShow || needsOnboarding || missingPermission else {
            return
        }

        if needsOnboarding && !forceShow && !previewToast {
            preferences.hasCompletedOnboarding = true
        }
        showSettings()
    }

    private func resolvedAppearanceOverride(from args: [String]) -> NSAppearance? {
        if args.contains("--appearance=light") {
            return NSAppearance(named: .aqua)
        }
        if args.contains("--appearance=dark") {
            return NSAppearance(named: .darkAqua)
        }
        return nil
    }

    // MARK: - Actions

    @discardableResult
    private func registerHotkey(_ binding: HotkeyBinding) -> Result<Void, HotkeyError> {
        hotkeyManager.register(binding) { [weak self] in
            self?.triggerCapture()
        }
    }

    private func triggerCapture() {
        capturer.capture(using: preferences)
    }

    private func openSaveFolder() {
        do {
            let url = try FileNamer.ensureWritableDirectory(at: preferences.saveDir)
            NSWorkspace.shared.open(url)
        } catch {
            Toast.showError(Strings.current().errorSaveFolderUnavailable)
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let args = CommandLine.arguments
            let permissionOverride: Bool? = args.contains("--preview-permission") ? false : nil
            settingsWindow = SettingsWindow(
                preferences: preferences,
                hotkeyManager: hotkeyManager,
                permissionOverride: permissionOverride,
                appearanceOverride: resolvedAppearanceOverride(from: args),
                onRegisterHotkey: { [weak self] binding in
                    guard let self else { return .failure(.unsupportedKey) }
                    return self.registerHotkey(binding)
                },
                onOpenFolder: { [weak self] in
                    self?.openSaveFolder()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        }
        settingsWindow?.show()
    }
}
