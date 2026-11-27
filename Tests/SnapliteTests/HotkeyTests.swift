import AppKit
import Carbon.HIToolbox
import Testing
@testable import SnapliteCore

@Suite("Hotkey")
struct HotkeyTests {
    private func failure(of result: Result<Void, HotkeyError>) -> HotkeyError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    @Test("Validator accepts default, modified shortcuts, and standalone F1-F20")
    func validatorAcceptsValidBindings() {
        #expect(failure(of: HotkeyValidator.validate(.default)) == nil)
        #expect(failure(of: HotkeyValidator.validate(HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(controlKey | shiftKey)
        ))) == nil)
        #expect(failure(of: HotkeyValidator.validate(HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(cmdKey | optionKey)
        ))) == nil)

        for fk in HotkeyValidator.functionKeyCodes {
            #expect(failure(of: HotkeyValidator.validate(HotkeyBinding(keyCode: fk, modifiers: 0))) == nil)
        }
    }

    @Test("Validator rejects missing modifiers for non-function keys")
    func validatorRejectsMissingModifier() {
        let nonFunctionKeys: [Int] = [kVK_ANSI_A, kVK_ANSI_4, kVK_Space, kVK_Return, kVK_UpArrow]
        for key in nonFunctionKeys {
            let binding = HotkeyBinding(keyCode: UInt32(key), modifiers: 0)
            #expect(failure(of: HotkeyValidator.validate(binding)) == .missingModifier)
        }
    }

    @Test("Validator rejects all system-reserved shortcuts")
    func validatorRejectsReservedCombos() {
        let reserved: [(Int, Int)] = [
            (kVK_ANSI_3, cmdKey | shiftKey),
            (kVK_ANSI_4, cmdKey | shiftKey),
            (kVK_ANSI_5, cmdKey | shiftKey),
            (kVK_ANSI_Q, cmdKey),
            (kVK_ANSI_W, cmdKey),
            (kVK_ANSI_H, cmdKey),
            (kVK_ANSI_M, cmdKey),
            (kVK_Tab, cmdKey),
            (kVK_Space, cmdKey)
        ]

        for (key, mods) in reserved {
            let binding = HotkeyBinding(keyCode: UInt32(key), modifiers: UInt32(mods))
            #expect(failure(of: HotkeyValidator.validate(binding)) == .reservedBySystem)
        }
    }

    @Test("Validator rejects standalone modifier keys")
    func validatorRejectsModifierKeys() {
        let binding = HotkeyBinding(keyCode: UInt32(kVK_Command), modifiers: UInt32(optionKey))
        #expect(failure(of: HotkeyValidator.validate(binding)) == .unsupportedKey)
    }

    @Test("Legacy v0.1 spec parser handles letters, digits, function keys, and special keys")
    func legacySpecParser() {
        #expect(HotkeyDisplay.parseLegacySpec("Alt+KeyA") == .default)
        #expect(HotkeyDisplay.parseLegacySpec("option+keya") == .default)
        #expect(HotkeyDisplay.parseLegacySpec("Cmd+Shift+Digit4") == HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(cmdKey | shiftKey)
        ))
        #expect(HotkeyDisplay.parseLegacySpec("Ctrl + Shift + KeyS") == HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(controlKey | shiftKey)
        ))
        #expect(HotkeyDisplay.parseLegacySpec("F2") == HotkeyBinding(
            keyCode: UInt32(kVK_F2),
            modifiers: 0
        ))
        #expect(HotkeyDisplay.parseLegacySpec("F19") == HotkeyBinding(
            keyCode: UInt32(kVK_F19),
            modifiers: 0
        ))
        #expect(HotkeyDisplay.parseLegacySpec("Alt+Space") == HotkeyBinding(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey)
        ))
        #expect(HotkeyDisplay.parseLegacySpec("Control+ArrowUp") == HotkeyBinding(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: UInt32(controlKey)
        ))
        #expect(HotkeyDisplay.parseLegacySpec("Cmd+Backspace") == HotkeyBinding(
            keyCode: UInt32(kVK_Delete),
            modifiers: UInt32(cmdKey)
        ))
        #expect(HotkeyDisplay.parseLegacySpec("Alt+Delete") == HotkeyBinding(
            keyCode: UInt32(kVK_ForwardDelete),
            modifiers: UInt32(optionKey)
        ))

        // Invalid specs
        #expect(HotkeyDisplay.parseLegacySpec("") == nil)
        #expect(HotkeyDisplay.parseLegacySpec("Alt+") == nil)
        #expect(HotkeyDisplay.parseLegacySpec("Alt") == nil)
        #expect(HotkeyDisplay.parseLegacySpec("Alt+KeyA+KeyB") == nil)
        #expect(HotkeyDisplay.parseLegacySpec("Alt+NotAKey") == nil)
    }

    @Test("Keycap tokens, compact display, and NSMenuItem keyEquivalent")
    @MainActor
    func displayTokensAndMenuEquivalents() {
        #expect(HotkeyDisplay.tokens(for: .default) == ["⌥", "A"])
        #expect(HotkeyDisplay.compactString(for: .default) == "⌥A")

        let allMods = HotkeyBinding(
            keyCode: UInt32(kVK_F6),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        #expect(HotkeyDisplay.tokens(for: allMods) == ["⌃", "⌥", "⇧", "⌘", "F6"])
        #expect(HotkeyDisplay.compactString(for: allMods) == "⌃⌥⇧⌘F6")

        let arrow = HotkeyBinding(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey))
        #expect(HotkeyDisplay.tokens(for: arrow) == ["⌥", "↑"])

        // Menu keyEquivalent MUST be lowercase for letters so AppKit doesn't inject Shift.
        let defaultMenu = HotkeyDisplay.menuKeyEquivalent(for: .default)
        #expect(defaultMenu.keyEquivalent == "a")
        #expect(defaultMenu.modifierMask == [.option])

        let shiftCmdS = HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        let shiftCmdSMenu = HotkeyDisplay.menuKeyEquivalent(for: shiftCmdS)
        #expect(shiftCmdSMenu.keyEquivalent == "s")
        #expect(shiftCmdSMenu.modifierMask == [.command, .shift])

        let f5 = HotkeyBinding(keyCode: UInt32(kVK_F5), modifiers: 0)
        let f5Menu = HotkeyDisplay.menuKeyEquivalent(for: f5)
        #expect(f5Menu.keyEquivalent == String(UnicodeScalar(NSF5FunctionKey)!))
        #expect(f5Menu.modifierMask == [])
    }

    @Test("NSEvent conversion and modifier roundtrip")
    @MainActor
    func nsEventConversion() throws {
        let flags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let carbon = HotkeyDisplay.carbonModifiers(from: flags)
        #expect(HotkeyDisplay.appKitModifiers(from: carbon) == flags)

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_A)
        ))
        let result = HotkeyDisplay.fromNSEvent(event)
        #expect(result == .success(HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(optionKey | shiftKey)
        )))

        let reservedEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_Q)
        ))
        #expect(HotkeyDisplay.fromNSEvent(reservedEvent) == .failure(.reservedBySystem))
    }

    @Test("HotkeyManager rejects invalid bindings and cleans up cleanly")
    @MainActor
    func managerLifecycle() {
        let manager = HotkeyManager()
        defer { manager.cleanup() }

        let invalid = HotkeyBinding(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey))
        #expect(failure(of: manager.register(invalid, action: {})) == .reservedBySystem)
        #expect(manager.currentBinding == nil)

        let valid = HotkeyBinding(
            keyCode: UInt32(kVK_F19),
            modifiers: UInt32(controlKey | optionKey | shiftKey)
        )
        let regResult = manager.register(valid, action: {})
        #expect(failure(of: regResult) == nil)
        #expect(manager.currentBinding == valid)

        manager.pause()
        #expect(manager.isPaused)
        manager.resume()
        #expect(!manager.isPaused)
        #expect(manager.currentBinding == valid)

        // Invalid re-registration preserves existing binding.
        #expect(failure(of: manager.register(
            HotkeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: 0),
            action: {}
        )) == .missingModifier)
        #expect(manager.currentBinding == valid)

        manager.cleanup()
        #expect(manager.currentBinding == nil)
    }

    @Test("Out-of-range keyCodes are safely rejected without trapping")
    @MainActor
    func outOfRangeKeyCodeHandledSafely() throws {
        let outOfRangeValues: [UInt32] = [UInt32(UInt16.max) + 1, UInt32.max]
        for keyCode in outOfRangeValues {
            let binding = HotkeyBinding(keyCode: keyCode, modifiers: UInt32(optionKey))
            #expect(failure(of: HotkeyValidator.validate(binding)) == .unsupportedKey)
            #expect(HotkeyDisplay.keyLabel(for: keyCode) == "Key\(keyCode)")
            #expect(HotkeyDisplay.tokens(for: binding) == ["⌥", "Key\(keyCode)"])
            let menu = HotkeyDisplay.menuKeyEquivalent(for: binding)
            #expect(menu.keyEquivalent.isEmpty)
            #expect(menu.modifierMask.isEmpty)
        }

        // Corrupted negative/overflow keyCode in UserDefaults falls back to default binding.
        let suite = "com.nekooo915.snaplite.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(-1, forKey: "snaplite.v2.hotkey.keyCode")
        defaults.set(Int(optionKey), forKey: "snaplite.v2.hotkey.modifiers")

        let prefs = Preferences(defaults: defaults)
        #expect(prefs.hotkey == .default)
    }
}
