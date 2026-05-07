import AppKit

/// Top-level coordinator. Wires the AppState (config + persistence) to
/// the menubar icon, the global hotkeys, and the settings window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var settings: SettingsWindowController!
    private var hotkeys: HotkeyManager!
    private var statusItem: NSStatusItem?

    // Tray menu items kept on the instance so we can retitle them after
    // a language change.
    private var miSettings: NSMenuItem!
    private var miRegion: NSMenuItem!
    private var miWindow: NSMenuItem!
    private var miQuit: NSMenuItem!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let initialConfig = Config.load()
        state = AppState(initial: initialConfig)
        settings = SettingsWindowController(state: state)
        hotkeys = HotkeyManager()

        applyAppearance(for: initialConfig)
        rebuildTrayMenu(for: initialConfig)
        rebindHotkeys(for: initialConfig)

        // Subsequent edits flow through here: persist → re-apply.
        state.onConfigChange = { [weak self] new in
            self?.handleConfigChange(new)
        }

        // Restore Dock visibility to whatever config implies after the
        // panel closes — the act of showing the window forces a brief
        // .regular activation that needs to be undone.
        settings.onClose = { [weak self] in
            guard let self else { return }
            self.applyAppearance(for: self.state.config)
        }

        SingleInstance.startListener { [weak self] in
            self?.showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unbindAll()
        SingleInstance.cleanup()
    }

    /// Triggered when the user re-launches the .app or clicks our Dock
    /// icon while we're already running. macOS does NOT spawn a second
    /// process in those cases, so the SingleInstance socket never fires;
    /// this delegate hook is the actual entry point.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Config change pipeline

    private func handleConfigChange(_ new: Config) {
        // Persist first so a crash mid-rebuild doesn't lose user input.
        do {
            try new.save()
        } catch {
            NSLog("[snaplite] failed to persist config: \(error)")
        }
        applyAppearance(for: new)
        rebuildTrayMenu(for: new)   // labels may have changed (language) and
                                    // hotkey hints may have changed too
        rebindHotkeys(for: new)
    }

    // MARK: - Appearance

    /// Apply the menubar-icon visibility. Dock visibility is *not*
    /// configurable: the Dock icon is shown only while the settings window
    /// is open, and otherwise stays hidden (the app runs as `.accessory`).
    private func applyAppearance(for config: Config) {
        if config.showTrayIcon {
            installMenubarIconIfNeeded()
        } else {
            removeMenubarIcon()
        }
        // Only fall back to the no-window default when the panel isn't
        // currently up; otherwise the user is mid-interaction and we'd
        // yank the Dock icon (and key window) out from under them.
        if !settings.isWindowVisible {
            DockIcon.setVisible(false)
        }
    }

    // MARK: - Menubar

    private func installMenubarIconIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = TrayIcon.makeImage()
        }
        statusItem = item
        // Build menu lazily; rebuildTrayMenu populates it.
    }

    private func removeMenubarIcon() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func rebuildTrayMenu(for config: Config) {
        guard let item = statusItem else { return }
        let s = Strings.table(for: Localization.resolve(config.language))

        let menu = NSMenu()

        miSettings = NSMenuItem(
            title: s.menuSettings,
            action: #selector(menuShowSettings),
            keyEquivalent: ""
        )
        miSettings.target = self

        miRegion = NSMenuItem(
            title: "\(s.menuCaptureRegion) (\(HotkeyParser.display(config.hotkeyRegion)))",
            action: #selector(menuCaptureRegion),
            keyEquivalent: ""
        )
        miRegion.target = self

        miWindow = NSMenuItem(
            title: "\(s.menuCaptureWindow) (\(HotkeyParser.display(config.hotkeyWindow)))",
            action: #selector(menuCaptureWindow),
            keyEquivalent: ""
        )
        miWindow.target = self

        miQuit = NSMenuItem(
            title: s.menuQuit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )

        menu.addItem(miSettings)
        menu.addItem(.separator())
        menu.addItem(miRegion)
        menu.addItem(miWindow)
        menu.addItem(.separator())
        menu.addItem(miQuit)

        item.menu = menu
    }

    // MARK: - Hotkeys

    private func rebindHotkeys(for config: Config) {
        let cfg = config
        hotkeys.bind(.region, spec: cfg.hotkeyRegion) { [weak self] in
            self?.captureRegion()
        }
        hotkeys.bind(.window, spec: cfg.hotkeyWindow) { [weak self] in
            self?.captureWindow()
        }
    }

    // MARK: - Actions

    @objc private func menuShowSettings() {
        showSettings()
    }

    @objc private func menuCaptureRegion() {
        captureRegion()
    }

    @objc private func menuCaptureWindow() {
        captureWindow()
    }

    private func showSettings() {
        // The Dock icon is bound to settings-window visibility — show it
        // for the duration of the panel, hide it again on close (handled
        // by `settings.onClose`). `.regular` is required for a hidden
        // app to surface a key window reliably.
        DockIcon.setVisible(true)
        settings.showWindow()
    }

    private func captureRegion() {
        Capture.run(mode: .region, config: state.config)
    }

    private func captureWindow() {
        Capture.run(mode: .window, config: state.config)
    }
}
