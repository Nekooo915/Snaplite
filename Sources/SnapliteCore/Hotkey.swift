import AppKit
import Carbon.HIToolbox

/// Validation or registration failures for a global hotkey.
public enum HotkeyError: Error, Equatable, Hashable, Sendable {
    case missingModifier
    case reservedBySystem
    case registrationFailed(OSStatus)
    case unsupportedKey

    public func localizedDescription(using strings: Strings) -> String {
        switch self {
        case .missingModifier:
            return strings.hotkeyErrorMissingModifier
        case .reservedBySystem:
            return strings.hotkeyErrorReserved
        case .registrationFailed:
            return strings.hotkeyErrorInUse
        case .unsupportedKey:
            return strings.hotkeyErrorUnsupported
        }
    }
}

/// Validates candidate hotkey bindings before registering with Carbon.
public enum HotkeyValidator {
    /// Virtual key codes for F1 through F20 (permitted without modifier keys).
    public static let functionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
        UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20)
    ]

    /// Standalone modifier virtual key codes that cannot be bound as the primary key.
    public static let modifierKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command), UInt32(kVK_RightCommand),
        UInt32(kVK_Shift), UInt32(kVK_RightShift),
        UInt32(kVK_CapsLock),
        UInt32(kVK_Option), UInt32(kVK_RightOption),
        UInt32(kVK_Control), UInt32(kVK_RightControl),
        UInt32(kVK_Function)
    ]

    /// System-reserved shortcuts that Snaplite refuses to hijack.
    public static let reservedBindings: Set<HotkeyBinding> = [
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey)),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey)),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey)),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey)),
        HotkeyBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)),
        HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
    ]

    public static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeyCodes.contains(keyCode)
    }

    public static func isModifierKey(_ keyCode: UInt32) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    public static func isReserved(_ binding: HotkeyBinding) -> Bool {
        reservedBindings.contains(binding)
    }

    public static func validate(_ binding: HotkeyBinding) -> Result<Void, HotkeyError> {
        if isModifierKey(binding.keyCode) {
            return .failure(.unsupportedKey)
        }
        let mods = binding.modifiers & HotkeyBinding.modifierMask
        if mods == 0 && !isFunctionKey(binding.keyCode) {
            return .failure(.missingModifier)
        }
        let normalized = HotkeyBinding(keyCode: binding.keyCode, modifiers: mods)
        if isReserved(normalized) {
            return .failure(.reservedBySystem)
        }
        return .success(())
    }
}

/// Formatting, event conversion, and legacy v0.1 spec parsing for hotkeys.
public enum HotkeyDisplay {
    // MARK: - Modifier Conversion

    /// Converts AppKit `NSEvent.ModifierFlags` into Carbon modifier flags.
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    /// Converts Carbon modifier flags into AppKit `NSEvent.ModifierFlags`.
    public static func appKitModifiers(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbon & UInt32(controlKey)) != 0 { flags.insert(.control) }
        if (carbon & UInt32(optionKey)) != 0 { flags.insert(.option) }
        if (carbon & UInt32(shiftKey)) != 0 { flags.insert(.shift) }
        if (carbon & UInt32(cmdKey)) != 0 { flags.insert(.command) }
        return flags
    }

    /// Modifier keycap tokens in canonical macOS HIG order (`⌃`, `⌥`, `⇧`, `⌘`).
    public static func modifierTokens(for modifiers: UInt32) -> [String] {
        var result: [String] = []
        if (modifiers & UInt32(controlKey)) != 0 { result.append("⌃") }
        if (modifiers & UInt32(optionKey)) != 0 { result.append("⌥") }
        if (modifiers & UInt32(shiftKey)) != 0 { result.append("⇧") }
        if (modifiers & UInt32(cmdKey)) != 0 { result.append("⌘") }
        return result
    }

    /// Converts a key-down `NSEvent` into a validated `HotkeyBinding`.
    @MainActor
    public static func fromNSEvent(_ event: NSEvent) -> Result<HotkeyBinding, HotkeyError> {
        let keyCode = UInt32(event.keyCode)
        let modifiers = carbonModifiers(from: event.modifierFlags)
        let binding = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
        switch HotkeyValidator.validate(binding) {
        case .success:
            return .success(binding)
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Keycap & Menu Rendering

    /// Individual keycap tokens (e.g. `["⌥", "A"]`) suitable for keycap UI rendering.
    @MainActor
    public static func tokens(for binding: HotkeyBinding) -> [String] {
        var result = modifierTokens(for: binding.modifiers)
        result.append(keyLabel(for: binding.keyCode))
        return result
    }

    /// Compact macOS shortcut string (e.g. `"⌥A"`).
    @MainActor
    public static func compactString(for binding: HotkeyBinding) -> String {
        tokens(for: binding).joined()
    }

    /// Human-readable label for a virtual key code using the active ASCII-capable keyboard layout.
    @MainActor
    public static func keyLabel(for keyCode: UInt32) -> String {
        if let special = specialKeyLabels[keyCode] {
            return special
        }
        if let translated = translateASCIIKeyCode(keyCode) {
            return translated.uppercased()
        }
        if let fallback = fallbackANSILabels[keyCode] {
            return fallback
        }
        return "Key\(keyCode)"
    }

    /// Returns `(keyEquivalent, modifierMask)` suitable for `NSMenuItem`.
    @MainActor
    public static func menuKeyEquivalent(
        for binding: HotkeyBinding
    ) -> (keyEquivalent: String, modifierMask: NSEvent.ModifierFlags) {
        let mask = appKitModifiers(from: binding.modifiers)
        if let special = specialMenuEquivalents[binding.keyCode] {
            return (special, mask)
        }
        if let translated = translateASCIIKeyCode(binding.keyCode) {
            // AppKit adds Shift automatically if keyEquivalent is uppercase.
            return (translated.lowercased(), mask)
        }
        if let fallback = fallbackANSILabels[binding.keyCode] {
            return (fallback.lowercased(), mask)
        }
        return ("", [])
    }

    @MainActor
    private static func translateASCIIKeyCode(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawPtr).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { rawBuffer -> String? in
            guard let layoutPtr = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var actualLength = 0
            let status = UCKeyTranslate(
                layoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )
            guard status == noErr, actualLength > 0 else { return nil }
            let translated = String(utf16CodeUnits: chars, count: actualLength)
                .trimmingCharacters(in: .controlCharacters)
            return translated.isEmpty ? nil : translated
        }
    }

    // MARK: - Legacy v0.1 Spec Parser

    /// Parses a v0.1 `global-hotkey` spec string (e.g. `"Alt+KeyA"`, `"Cmd+Shift+Digit4"`, `"F2"`).
    public static func parseLegacySpec(_ spec: String) -> HotkeyBinding? {
        var modifiers: UInt32 = 0
        var keyCode: UInt32?

        for raw in spec.split(separator: "+") {
            let token = raw.trimmingCharacters(in: .whitespaces).uppercased()
            guard !token.isEmpty else { return nil }
            switch token {
            case "CTRL", "CONTROL":
                modifiers |= UInt32(controlKey)
            case "ALT", "OPTION":
                modifiers |= UInt32(optionKey)
            case "SHIFT":
                modifiers |= UInt32(shiftKey)
            case "CMD", "COMMAND", "META", "SUPER", "WIN":
                modifiers |= UInt32(cmdKey)
            default:
                guard keyCode == nil, let parsed = legacyKeyCode(for: token) else {
                    return nil
                }
                keyCode = parsed
            }
        }

        guard let resolvedKeyCode = keyCode else { return nil }
        return HotkeyBinding(keyCode: resolvedKeyCode, modifiers: modifiers)
    }

    private static func legacyKeyCode(for upperToken: String) -> UInt32? {
        if upperToken.hasPrefix("KEY"), upperToken.count == 4, let c = upperToken.last {
            return legacyLetters[c]
        }
        if upperToken.hasPrefix("DIGIT"), upperToken.count == 6, let c = upperToken.last {
            return legacyDigits[c]
        }
        return legacyMiscKeys[upperToken]
    }

    // MARK: - Key Tables

    private static let specialKeyLabels: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_ANSI_KeypadEnter): "↩",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟"
    ]

    private static let specialMenuEquivalents: [UInt32: String] = {
        var map: [UInt32: String] = [
            UInt32(kVK_Space): " ",
            UInt32(kVK_Tab): "\t",
            UInt32(kVK_Return): "\r",
            UInt32(kVK_ANSI_KeypadEnter): "\r",
            UInt32(kVK_Escape): "\u{1B}",
            UInt32(kVK_Delete): String(UnicodeScalar(NSBackspaceCharacter)!),
            UInt32(kVK_ForwardDelete): String(UnicodeScalar(NSDeleteFunctionKey)!),
            UInt32(kVK_UpArrow): String(UnicodeScalar(NSUpArrowFunctionKey)!),
            UInt32(kVK_DownArrow): String(UnicodeScalar(NSDownArrowFunctionKey)!),
            UInt32(kVK_LeftArrow): String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            UInt32(kVK_RightArrow): String(UnicodeScalar(NSRightArrowFunctionKey)!),
            UInt32(kVK_Home): String(UnicodeScalar(NSHomeFunctionKey)!),
            UInt32(kVK_End): String(UnicodeScalar(NSEndFunctionKey)!),
            UInt32(kVK_PageUp): String(UnicodeScalar(NSPageUpFunctionKey)!),
            UInt32(kVK_PageDown): String(UnicodeScalar(NSPageDownFunctionKey)!)
        ]
        let fKeyCodes: [Int] = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        for (offset, vk) in fKeyCodes.enumerated() {
            if let scalar = UnicodeScalar(NSF1FunctionKey + offset) {
                map[UInt32(vk)] = String(scalar)
            }
        }
        return map
    }()

    private static let fallbackANSILabels: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9"
    ]

    private static let legacyLetters: [Character: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z)
    ]

    private static let legacyDigits: [Character: UInt32] = [
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9)
    ]

    private static let legacyMiscKeys: [String: UInt32] = [
        "F1": UInt32(kVK_F1), "F2": UInt32(kVK_F2), "F3": UInt32(kVK_F3), "F4": UInt32(kVK_F4),
        "F5": UInt32(kVK_F5), "F6": UInt32(kVK_F6), "F7": UInt32(kVK_F7), "F8": UInt32(kVK_F8),
        "F9": UInt32(kVK_F9), "F10": UInt32(kVK_F10), "F11": UInt32(kVK_F11), "F12": UInt32(kVK_F12),
        "F13": UInt32(kVK_F13), "F14": UInt32(kVK_F14), "F15": UInt32(kVK_F15), "F16": UInt32(kVK_F16),
        "F17": UInt32(kVK_F17), "F18": UInt32(kVK_F18), "F19": UInt32(kVK_F19), "F20": UInt32(kVK_F20),
        "SPACE": UInt32(kVK_Space),
        "TAB": UInt32(kVK_Tab),
        "ENTER": UInt32(kVK_Return),
        "RETURN": UInt32(kVK_Return),
        "ESCAPE": UInt32(kVK_Escape),
        "BACKSPACE": UInt32(kVK_Delete),
        "DELETE": UInt32(kVK_ForwardDelete),
        "ARROWUP": UInt32(kVK_UpArrow),
        "ARROWDOWN": UInt32(kVK_DownArrow),
        "ARROWLEFT": UInt32(kVK_LeftArrow),
        "ARROWRIGHT": UInt32(kVK_RightArrow)
    ]
}

/// Manages the single Carbon global hotkey registration with rollback, pause/resume,
/// and deterministic handler cleanup.
@MainActor
public final class HotkeyManager {
    private static let signature: OSType = 0x534E_4150 // 'SNAP'
    private static let hotKeyID: UInt32 = 1

    /// Thread-safe holder for Carbon opaque refs so `deinit` (nonisolated under macOS 14 target)
    /// can cleanly unregister both the hotkey and the event handler without Swift 6 warnings.
    private final class CarbonHandles: @unchecked Sendable {
        private let lock = NSLock()
        private var hotKeyRef: EventHotKeyRef?
        private var handlerRef: EventHandlerRef?

        var hasHandler: Bool {
            lock.lock()
            defer { lock.unlock() }
            return handlerRef != nil
        }

        func setHandler(_ ref: EventHandlerRef) {
            lock.lock()
            handlerRef = ref
            lock.unlock()
        }

        func setHotKey(_ ref: EventHotKeyRef) {
            lock.lock()
            let old = hotKeyRef
            hotKeyRef = ref
            lock.unlock()
            if let old {
                UnregisterEventHotKey(old)
            }
        }

        func unregisterHotKey() {
            lock.lock()
            let old = hotKeyRef
            hotKeyRef = nil
            lock.unlock()
            if let old {
                UnregisterEventHotKey(old)
            }
        }

        func removeHandler() {
            lock.lock()
            let old = handlerRef
            handlerRef = nil
            lock.unlock()
            if let old {
                RemoveEventHandler(old)
            }
        }

        func cleanupAll() {
            unregisterHotKey()
            removeHandler()
        }

        deinit {
            cleanupAll()
        }
    }

    public private(set) var currentBinding: HotkeyBinding?
    public private(set) var isPaused: Bool = false

    private var currentAction: (@MainActor () -> Void)?
    private let handles = CarbonHandles()

    public init() {}

    deinit {
        handles.cleanupAll()
    }

    /// Registers a single global hotkey. Validates first; on Carbon failure rolls back
    /// to the previously registered binding and returns `.failure(.registrationFailed(status))`.
    @discardableResult
    public func register(
        _ binding: HotkeyBinding,
        action: @escaping @MainActor () -> Void
    ) -> Result<Void, HotkeyError> {
        let normalized = HotkeyBinding(keyCode: binding.keyCode, modifiers: binding.modifiers)
        if case .failure(let error) = HotkeyValidator.validate(normalized) {
            return .failure(error)
        }

        if let handlerStatus = installHandlerIfNeeded(), handlerStatus != noErr {
            return .failure(.registrationFailed(handlerStatus))
        }

        let previousBinding = currentBinding
        let previousAction = currentAction

        handles.unregisterHotKey()

        let status = registerCarbonHotKey(normalized)
        guard status == noErr else {
            // Roll back to previous binding.
            currentBinding = previousBinding
            currentAction = previousAction
            if !isPaused, let previousBinding {
                _ = registerCarbonHotKey(previousBinding)
            }
            return .failure(.registrationFailed(status))
        }

        currentBinding = normalized
        currentAction = action

        // If currently paused (e.g. recording), keep the verified binding stored
        // but release the Carbon grab until `resume()` is called.
        if isPaused {
            handles.unregisterHotKey()
        }

        return .success(())
    }

    /// Temporarily unregisters the active hotkey (e.g. while recording a new shortcut)
    /// so keystrokes reach the local event monitor instead of firing a capture.
    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        handles.unregisterHotKey()
    }

    /// Re-registers the stored hotkey after `pause()`.
    public func resume() {
        guard isPaused else { return }
        isPaused = false
        if let binding = currentBinding {
            _ = registerCarbonHotKey(binding)
        }
    }

    /// Unregisters the active hotkey and clears the stored binding and action.
    public func unregister() {
        handles.unregisterHotKey()
        currentBinding = nil
        currentAction = nil
    }

    /// Unregisters the active hotkey and removes the Carbon event handler.
    public func cleanup() {
        unregister()
        handles.removeHandler()
    }

    // MARK: - Carbon Bridge

    private func registerCarbonHotKey(_ binding: HotkeyBinding) -> OSStatus {
        var hotKeyRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            handles.setHotKey(ref)
        }
        return status
    }

    private func installHandlerIfNeeded() -> OSStatus? {
        guard !handles.hasHandler else { return nil }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let trampoline: EventHandlerUPP = { _, eventRef, userData -> OSStatus in
            guard let eventRef, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            guard hotKeyID.signature == HotkeyManager.signature else {
                return OSStatus(eventNotHandledErr)
            }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            Task { @MainActor [weak manager] in
                manager?.dispatchHotKey(id: id)
            }
            return noErr
        }

        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            trampoline,
            1,
            &spec,
            context,
            &handlerRef
        )
        if status == noErr, let handlerRef {
            handles.setHandler(handlerRef)
        }
        return status
    }

    private func dispatchHotKey(id: UInt32) {
        guard id == Self.hotKeyID, !isPaused else { return }
        currentAction?()
    }
}
