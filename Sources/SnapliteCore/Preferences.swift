import Carbon.HIToolbox
import Foundation
import Observation

/// What happens after a screenshot is captured.
public enum OutputMode: String, Codable, CaseIterable, Sendable {
    case copy
    case save
    case both
}

/// Carbon virtual key code + Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public static let modifierMask: UInt32 = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    /// Default capture shortcut: `⌥A`.
    public static let `default` = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(optionKey)
    )

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }
}

/// Persistent app preferences backed by `UserDefaults`, observed via `@Observable` (no Combine).
@Observable
@MainActor
public final class Preferences {
    private enum Key {
        static let outputMode = "snaplite.v2.outputMode"
        static let saveDir = "snaplite.v2.saveDir"
        static let showTrayIcon = "snaplite.v2.showTrayIcon"
        static let showToast = "snaplite.v2.showToast"
        static let hotkeyKeyCode = "snaplite.v2.hotkey.keyCode"
        static let hotkeyModifiers = "snaplite.v2.hotkey.modifiers"
        static let hasCompletedOnboarding = "snaplite.v2.hasCompletedOnboarding"
        static let migratedFromV1 = "snaplite.v2.migratedFromV1"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Invoked whenever `hotkey` changes to a new value.
    @ObservationIgnored public var onHotkeyChange: (@MainActor (HotkeyBinding) -> Void)?

    /// Invoked whenever `showTrayIcon` changes to a new value.
    @ObservationIgnored public var onTrayVisibilityChange: (@MainActor (Bool) -> Void)?

    /// Invoked whenever any user-facing preference changes.
    @ObservationIgnored public var onChange: (@MainActor (Preferences) -> Void)?

    public var outputMode: OutputMode {
        didSet {
            guard outputMode != oldValue else { return }
            defaults.set(outputMode.rawValue, forKey: Key.outputMode)
            onChange?(self)
        }
    }

    public var saveDir: String {
        didSet {
            guard saveDir != oldValue else { return }
            defaults.set(saveDir, forKey: Key.saveDir)
            onChange?(self)
        }
    }

    public var showTrayIcon: Bool {
        didSet {
            guard showTrayIcon != oldValue else { return }
            defaults.set(showTrayIcon, forKey: Key.showTrayIcon)
            onTrayVisibilityChange?(showTrayIcon)
            onChange?(self)
        }
    }

    public var showToast: Bool {
        didSet {
            guard showToast != oldValue else { return }
            defaults.set(showToast, forKey: Key.showToast)
            onChange?(self)
        }
    }

    public var hotkey: HotkeyBinding {
        didSet {
            guard hotkey != oldValue else { return }
            defaults.set(Int(hotkey.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(hotkey.modifiers), forKey: Key.hotkeyModifiers)
            onHotkeyChange?(hotkey)
            onChange?(self)
        }
    }

    /// Tracks whether the settings window has already been presented on initial launch
    /// so subsequent or login launches remain quiet in the background.
    public var hasCompletedOnboarding: Bool {
        didSet {
            guard hasCompletedOnboarding != oldValue else { return }
            defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        }
    }

    /// Save directory path abbreviated with `~` for display.
    public var displaySaveDir: String {
        (saveDir as NSString).abbreviatingWithTildeInPath
    }

    /// Creates a `Preferences` instance backed by `defaults`.
    ///
    /// One-time migration from v0.1 `config.json` runs automatically when using
    /// `UserDefaults.standard` or when `legacyConfigURL` is explicitly provided.
    public init(
        defaults: UserDefaults = .standard,
        legacyConfigURL: URL? = nil,
        autoMigrate: Bool? = nil
    ) {
        self.defaults = defaults

        let shouldMigrate = autoMigrate ?? (defaults === UserDefaults.standard || legacyConfigURL != nil)
        if shouldMigrate {
            let url = legacyConfigURL ?? Self.defaultLegacyConfigURL()
            _ = Self.migrateLegacyConfig(from: url, into: defaults)
        }

        let defaultDir = Self.defaultSaveDir().path

        if let rawMode = defaults.string(forKey: Key.outputMode),
           let parsedMode = OutputMode(rawValue: rawMode) {
            self.outputMode = parsedMode
        } else {
            self.outputMode = .both
        }

        if let storedDir = defaults.string(forKey: Key.saveDir), !storedDir.isEmpty {
            self.saveDir = storedDir
        } else {
            self.saveDir = defaultDir
        }

        if let storedTray = defaults.object(forKey: Key.showTrayIcon) as? Bool {
            self.showTrayIcon = storedTray
        } else {
            self.showTrayIcon = true
        }

        if let storedToast = defaults.object(forKey: Key.showToast) as? Bool {
            self.showToast = storedToast
        } else {
            self.showToast = false
        }

        if let keyNum = defaults.object(forKey: Key.hotkeyKeyCode) as? NSNumber,
           let modNum = defaults.object(forKey: Key.hotkeyModifiers) as? NSNumber {
            let binding = HotkeyBinding(
                keyCode: keyNum.uint32Value,
                modifiers: modNum.uint32Value
            )
            if case .success = HotkeyValidator.validate(binding) {
                self.hotkey = binding
            } else {
                self.hotkey = .default
            }
        } else {
            self.hotkey = .default
        }

        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    /// Resets `hotkey` back to the default (`⌥A`).
    public func resetHotkeyToDefault() {
        hotkey = .default
    }

    // MARK: - Default Paths

    public static func defaultSaveDir(fileManager: FileManager = .default) -> URL {
        let pictures = fileManager
            .urls(for: .picturesDirectory, in: .userDomainMask)
            .first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Snaplite", isDirectory: true)
    }

    public static func defaultLegacyConfigURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Snaplite", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    // MARK: - One-Time v0.1 Migration

    /// Wire format of Snaplite v0.1 `config.json`.
    private struct LegacyConfigV1: Decodable {
        let saveToFile: Bool?
        let copyToClipboard: Bool?
        let saveDir: String?
        let showTrayIcon: Bool?
        let hotkeyRegion: String?
    }

    /// Migrates v0.1 `config.json` into `defaults` at most once.
    /// Returns `true` if a legacy file was found, decoded, and migrated; `false` otherwise.
    @discardableResult
    public static func migrateLegacyConfig(
        from url: URL,
        into defaults: UserDefaults,
        fileManager: FileManager = .default
    ) -> Bool {
        guard !defaults.bool(forKey: Key.migratedFromV1) else {
            return false
        }

        defer {
            defaults.set(true, forKey: Key.migratedFromV1)
        }

        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder().decode(LegacyConfigV1.self, from: data) else {
            return false
        }

        // Preserve any values already written in v0.2 rather than overwriting them.
        if defaults.object(forKey: Key.outputMode) == nil {
            let saveToFile = legacy.saveToFile ?? true
            let copyToClipboard = legacy.copyToClipboard ?? true
            let mode: OutputMode = switch (saveToFile, copyToClipboard) {
            case (true, true): .both
            case (true, false): .save
            case (false, true): .copy
            case (false, false): .both
            }
            defaults.set(mode.rawValue, forKey: Key.outputMode)
        }

        if defaults.object(forKey: Key.saveDir) == nil,
           let dir = legacy.saveDir, !dir.isEmpty {
            defaults.set(dir, forKey: Key.saveDir)
        }

        if defaults.object(forKey: Key.showTrayIcon) == nil,
           let showTray = legacy.showTrayIcon {
            defaults.set(showTray, forKey: Key.showTrayIcon)
        }

        if defaults.object(forKey: Key.hotkeyKeyCode) == nil,
           let rawHotkey = legacy.hotkeyRegion,
           let parsed = HotkeyDisplay.parseLegacySpec(rawHotkey),
           case .success = HotkeyValidator.validate(parsed) {
            defaults.set(Int(parsed.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(parsed.modifiers), forKey: Key.hotkeyModifiers)
        }

        return true
    }
}
