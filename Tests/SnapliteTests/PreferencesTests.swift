import Carbon.HIToolbox
import Foundation
import Testing
@testable import SnapliteCore

@Suite("Preferences")
struct PreferencesTests {
    private func makeEphemeralDefaults() throws -> (UserDefaults, String) {
        let suite = "com.nekooo915.snaplite.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func writeTempJSON(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplite-v1-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url
    }

    @Test("Provides expected defaults on a clean UserDefaults suite")
    @MainActor
    func defaults() throws {
        let (defaults, suite) = try makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.outputMode == .both)
        #expect(prefs.saveDir == Preferences.defaultSaveDir().path)
        #expect(prefs.showTrayIcon == true)
        #expect(prefs.showToast == false)
        #expect(prefs.hotkey == .default)
        #expect(prefs.hotkey.keyCode == UInt32(kVK_ANSI_A))
        #expect(prefs.hotkey.modifiers == UInt32(optionKey))
        #expect(prefs.hasCompletedOnboarding == false)
    }

    @Test("Persists all fields across instances and deduplicates callbacks")
    @MainActor
    func persistenceAndCallbacks() throws {
        let (defaults, suite) = try makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = Preferences(defaults: defaults)
        var hotkeyCallbacks: [HotkeyBinding] = []
        var trayCallbacks: [Bool] = []
        var generalChangeCount = 0

        prefs.onHotkeyChange = { hotkeyCallbacks.append($0) }
        prefs.onTrayVisibilityChange = { trayCallbacks.append($0) }
        prefs.onChange = { _ in generalChangeCount += 1 }

        // Redundant writes must not fire callbacks.
        prefs.outputMode = .both
        prefs.showTrayIcon = true
        prefs.hotkey = .default
        #expect(hotkeyCallbacks.isEmpty)
        #expect(trayCallbacks.isEmpty)
        #expect(generalChangeCount == 0)

        // Mutate every property.
        let customHotkey = HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_A), // 0! Explicitly tests zero keyCode persistence.
            modifiers: UInt32(controlKey | shiftKey)
        )
        prefs.outputMode = .copy
        prefs.saveDir = "/tmp/SnapliteCustom"
        prefs.showTrayIcon = false
        prefs.showToast = true
        prefs.hotkey = customHotkey
        prefs.hasCompletedOnboarding = true

        #expect(hotkeyCallbacks == [customHotkey])
        #expect(trayCallbacks == [false])
        #expect(generalChangeCount == 5)

        // Reload in a fresh instance backed by the same UserDefaults.
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.outputMode == .copy)
        #expect(reloaded.saveDir == "/tmp/SnapliteCustom")
        #expect(reloaded.showTrayIcon == false)
        #expect(reloaded.showToast == true)
        #expect(reloaded.hotkey == customHotkey)
        #expect(reloaded.hasCompletedOnboarding == true)

        reloaded.resetHotkeyToDefault()
        #expect(reloaded.hotkey == .default)
    }

    @Test("Migrates all saveToFile / copyToClipboard combinations from v0.1 config.json")
    @MainActor
    func migrateOutputModes() throws {
        let cases: [(saveToFile: Bool, copyToClipboard: Bool, expected: OutputMode)] = [
            (true, true, .both),
            (true, false, .save),
            (false, true, .copy),
            (false, false, .both)
        ]

        for testCase in cases {
            let (defaults, suite) = try makeEphemeralDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }

            let json = """
            {
              "saveToFile": \(testCase.saveToFile),
              "copyToClipboard": \(testCase.copyToClipboard),
              "saveDir": "/Users/test/Screenshots",
              "showTrayIcon": false,
              "hotkeyRegion": "Ctrl+Shift+KeyS",
              "hotkeyWindow": "Alt+KeyS",
              "language": "zh"
            }
            """
            let url = try writeTempJSON(json)
            defer { try? FileManager.default.removeItem(at: url) }

            let prefs = Preferences(defaults: defaults, legacyConfigURL: url)
            #expect(prefs.outputMode == testCase.expected)
            #expect(prefs.saveDir == "/Users/test/Screenshots")
            #expect(prefs.showTrayIcon == false)
            #expect(prefs.showToast == false)
            #expect(prefs.hotkey == HotkeyBinding(
                keyCode: UInt32(kVK_ANSI_S),
                modifiers: UInt32(controlKey | shiftKey)
            ))
        }
    }

    @Test("v0.1 migration runs only once and falls back safely on invalid hotkey or corrupt JSON")
    @MainActor
    func migrationIdempotencyAndFallbacks() throws {
        let (defaults, suite) = try makeEphemeralDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let url = try writeTempJSON("""
        {
          "saveToFile": false,
          "copyToClipboard": true,
          "saveDir": "/Users/test/Snaps",
          "showTrayIcon": true,
          "hotkeyRegion": "Cmd+KeyQ"
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let prefs = Preferences(defaults: defaults, legacyConfigURL: url)
        #expect(prefs.outputMode == .copy)
        // Reserved Cmd+Q from v0.1 must fall back to default ⌥A.
        #expect(prefs.hotkey == .default)

        // User edits preferences in v0.2.
        prefs.outputMode = .save
        prefs.saveDir = "/Users/test/NewDir"

        // Re-running migration must be a no-op.
        let ranAgain = Preferences.migrateLegacyConfig(from: url, into: defaults)
        #expect(ranAgain == false)

        let reloaded = Preferences(defaults: defaults, legacyConfigURL: url)
        #expect(reloaded.outputMode == .save)
        #expect(reloaded.saveDir == "/Users/test/NewDir")

        // Corrupt JSON never crashes.
        let (corruptDefaults, corruptSuite) = try makeEphemeralDefaults()
        defer { corruptDefaults.removePersistentDomain(forName: corruptSuite) }

        let corruptURL = try writeTempJSON("{ not valid json")
        defer { try? FileManager.default.removeItem(at: corruptURL) }

        let migratedCorrupt = Preferences.migrateLegacyConfig(from: corruptURL, into: corruptDefaults)
        #expect(migratedCorrupt == false)
        let fallbackPrefs = Preferences(defaults: corruptDefaults)
        #expect(fallbackPrefs.outputMode == .both)
        #expect(fallbackPrefs.hotkey == .default)
    }
}
