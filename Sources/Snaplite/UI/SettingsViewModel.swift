import AppKit
import Carbon.HIToolbox
import Observation
import SnapliteCore

/// Observable state and actions for the on-demand Settings window.
/// Holds all transient UI state so SwiftUI views never need `@State` (CLT 27.2 compatible).
@Observable
@MainActor
final class SettingsViewModel {
    let preferences: Preferences
    let strings: Strings
    let appVersion: String

    var isPermissionGranted: Bool
    var launchAtLogin: Bool
    var loginItemError: String?
    var isRecordingHotkey: Bool = false
    var hotkeyError: String?
    var hotkeyShakeTrigger: CGFloat = 0
    var isDropTargeted: Bool = false
    var folderError: String?

    @ObservationIgnored weak var hostWindow: NSWindow?
    @ObservationIgnored private let permissionOverride: Bool?
    @ObservationIgnored private let hotkeyManager: HotkeyManager
    @ObservationIgnored private let onRegisterHotkey: @MainActor (HotkeyBinding) -> Result<Void, HotkeyError>
    @ObservationIgnored private let onOpenFolder: @MainActor () -> Void
    @ObservationIgnored private let onQuit: @MainActor () -> Void
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var hotkeyErrorClearWorkItem: DispatchWorkItem?
    @ObservationIgnored private var loginErrorClearWorkItem: DispatchWorkItem?
    @ObservationIgnored private var folderErrorClearWorkItem: DispatchWorkItem?

    init(
        preferences: Preferences,
        hotkeyManager: HotkeyManager,
        permissionOverride: Bool? = nil,
        onRegisterHotkey: @escaping @MainActor (HotkeyBinding) -> Result<Void, HotkeyError>,
        onOpenFolder: @escaping @MainActor () -> Void,
        onQuit: @escaping @MainActor () -> Void
    ) {
        self.preferences = preferences
        self.strings = Strings.current()
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.2.0"
        self.permissionOverride = permissionOverride
        self.isPermissionGranted = permissionOverride ?? Permission.isGranted
        self.launchAtLogin = LoginItem.isEnabled
        self.hotkeyManager = hotkeyManager
        self.onRegisterHotkey = onRegisterHotkey
        self.onOpenFolder = onOpenFolder
        self.onQuit = onQuit
    }

    // MARK: - Lifecycle & System Refresh

    func refreshSystemState() {
        isPermissionGranted = permissionOverride ?? Permission.isGranted
        launchAtLogin = LoginItem.isEnabled
    }

    func cleanupOnWindowClose() {
        stopRecordingHotkey()
        hotkeyErrorClearWorkItem?.cancel()
        hotkeyErrorClearWorkItem = nil
        loginErrorClearWorkItem?.cancel()
        loginErrorClearWorkItem = nil
        folderErrorClearWorkItem?.cancel()
        folderErrorClearWorkItem = nil
    }

    // MARK: - Permission Actions

    func handlePermissionPillClick() {
        if !isPermissionGranted {
            Permission.requestAccess()
        }
        Permission.openSystemSettings()
    }

    func openSystemSettings() {
        Permission.requestAccess()
        Permission.openSystemSettings()
    }

    func relaunchApp() {
        Permission.relaunchApp()
    }

    // MARK: - Hotkey Recording

    func startRecordingHotkey() {
        guard !isRecordingHotkey else { return }
        clearHotkeyError()
        isRecordingHotkey = true
        hotkeyManager.pause()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let keyCode = UInt32(event.keyCode)
            let modifierFlags = event.modifierFlags
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleRecordedKey(keyCode: keyCode, modifierFlags: modifierFlags)
            }
            return consumed ? nil : event
        }
    }

    func stopRecordingHotkey() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if isRecordingHotkey {
            isRecordingHotkey = false
        }
        hotkeyManager.resume()
    }

    func resetHotkeyToDefault() {
        stopRecordingHotkey()
        let result = onRegisterHotkey(.default)
        switch result {
        case .success:
            preferences.hotkey = .default
            clearHotkeyError()
        case .failure(let error):
            presentHotkeyError(error)
        }
    }

    private func handleRecordedKey(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard isRecordingHotkey else { return false }

        let relevantModifiers = modifierFlags.intersection([.command, .option, .control, .shift])
        if keyCode == UInt32(kVK_Escape) && relevantModifiers.isEmpty {
            clearHotkeyError()
            stopRecordingHotkey()
            return true
        }

        let binding = HotkeyBinding(
            keyCode: keyCode,
            modifiers: HotkeyDisplay.carbonModifiers(from: modifierFlags)
        )
        switch HotkeyValidator.validate(binding) {
        case .failure(let error):
            presentHotkeyError(error)
            return true
        case .success:
            switch onRegisterHotkey(binding) {
            case .success:
                preferences.hotkey = binding
                clearHotkeyError()
                stopRecordingHotkey()
            case .failure(let error):
                presentHotkeyError(error)
            }
            return true
        }
    }

    private func presentHotkeyError(_ error: HotkeyError) {
        hotkeyErrorClearWorkItem?.cancel()
        hotkeyError = error.localizedDescription(using: strings)
        hotkeyShakeTrigger += 1

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.hotkeyError = nil
            }
        }
        hotkeyErrorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }

    private func clearHotkeyError() {
        hotkeyErrorClearWorkItem?.cancel()
        hotkeyErrorClearWorkItem = nil
        hotkeyError = nil
    }

    // MARK: - Save Folder

    func chooseSaveFolder() {
        stopRecordingHotkey()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        let expanded = (preferences.saveDir as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)

        if let window = hostWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                Task { @MainActor [weak self] in
                    _ = self?.applySaveFolder(url)
                }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            _ = applySaveFolder(url)
        }
    }

    func openSaveFolder() {
        onOpenFolder()
    }

    func handleFolderDrop(urls: [URL]) -> Bool {
        guard let url = urls.first(where: { $0.isFileURL }) else {
            return false
        }
        return applySaveFolder(url)
    }

    @discardableResult
    private func applySaveFolder(_ url: URL) -> Bool {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDir else {
            presentFolderError()
            return false
        }
        do {
            let resolved = try FileNamer.ensureWritableDirectory(at: url.path)
            preferences.saveDir = resolved.path
            folderErrorClearWorkItem?.cancel()
            folderError = nil
            return true
        } catch {
            presentFolderError()
            return false
        }
    }

    private func presentFolderError() {
        folderErrorClearWorkItem?.cancel()
        folderError = strings.errorSaveFolderUnavailable
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.folderError = nil
            }
        }
        folderErrorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: workItem)
    }

    // MARK: - Login Item & Quit

    func setLaunchAtLogin(_ enabled: Bool) {
        loginErrorClearWorkItem?.cancel()
        loginItemError = nil
        do {
            try LoginItem.setEnabled(enabled)
            launchAtLogin = LoginItem.isEnabled
        } catch {
            launchAtLogin = LoginItem.isEnabled
            loginItemError = strings.errorLoginItemFailed
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.loginItemError = nil
                }
            }
            loginErrorClearWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
        }
    }

    func quit() {
        onQuit()
    }
}
