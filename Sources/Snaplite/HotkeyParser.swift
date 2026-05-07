import AppKit
import Carbon.HIToolbox

/// Hotkey strings.
///
/// We keep wire-compatible with the Rust build's TOML config, which uses
/// `global-hotkey` syntax (e.g. `Alt+KeyA`, `Cmd+Shift+KeyS`, `F2`). Two
/// jobs here:
///
/// - `parse(_:)` converts a spec into the (keyCode, modifiers) tuple that
///   Carbon's `RegisterEventHotKey` expects.
/// - `display(_:)` renders the same spec as a compact mac-style label
///   (`⌥A`, `⌃⇧F2`) for the panel and tray menu.
enum HotkeyParser {
    struct Parsed {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    static func parse(_ spec: String) -> Parsed? {
        var modifiers: UInt32 = 0
        var keyCode: UInt32? = nil

        for raw in spec.split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces).uppercased()
            switch part {
            case "CTRL", "CONTROL":
                modifiers |= UInt32(controlKey)
            case "ALT", "OPTION":
                modifiers |= UInt32(optionKey)
            case "SHIFT":
                modifiers |= UInt32(shiftKey)
            case "CMD", "COMMAND", "META", "SUPER", "WIN":
                modifiers |= UInt32(cmdKey)
            default:
                guard let kc = keyCodeFromName(part) else { return nil }
                if keyCode != nil { return nil }   // multiple non-modifier keys
                keyCode = kc
            }
        }
        guard let kc = keyCode else { return nil }
        return Parsed(keyCode: kc, modifiers: modifiers)
    }

    /// Render a hotkey spec for display (mac-style glyphs).
    static func display(_ spec: String) -> String {
        var out = ""
        for raw in spec.split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces).uppercased()
            switch part {
            case "CTRL", "CONTROL": out.append("⌃")
            case "ALT", "OPTION": out.append("⌥")
            case "SHIFT": out.append("⇧")
            case "CMD", "COMMAND", "META", "SUPER", "WIN": out.append("⌘")
            default: out.append(prettyKeyName(part))
            }
        }
        return out
    }

    private static func prettyKeyName(_ upper: String) -> String {
        if upper.hasPrefix("KEY") {
            return String(upper.dropFirst(3))
        }
        if upper.hasPrefix("DIGIT") {
            return String(upper.dropFirst(5))
        }
        switch upper {
        case "ARROWUP": return "↑"
        case "ARROWDOWN": return "↓"
        case "ARROWLEFT": return "←"
        case "ARROWRIGHT": return "→"
        case "SPACE": return "Space"
        case "TAB": return "Tab"
        case "ENTER", "RETURN": return "⏎"
        case "ESCAPE": return "⎋"
        case "BACKSPACE": return "⌫"
        case "DELETE": return "⌦"
        default:
            // Function keys (F1...F12) read fine as-is. Anything else, just
            // title-case so unknown codes are at least readable.
            if upper.first == "F", upper.dropFirst().allSatisfy(\.isNumber) {
                return upper
            }
            return upper.prefix(1) + upper.dropFirst().lowercased()
        }
    }

    // MARK: - keyCode mapping

    /// global-hotkey-style spec name → macOS virtual key code.
    static func keyCodeFromName(_ upper: String) -> UInt32? {
        if upper.hasPrefix("KEY"), upper.count == 4 {
            return letterKeyCode(upper.last!)
        }
        if upper.hasPrefix("DIGIT"), upper.count == 6 {
            return digitKeyCode(upper.last!)
        }
        return Self.miscKeyCodes[upper]
    }

    private static func letterKeyCode(_ c: Character) -> UInt32? {
        switch c {
        case "A": return UInt32(kVK_ANSI_A)
        case "B": return UInt32(kVK_ANSI_B)
        case "C": return UInt32(kVK_ANSI_C)
        case "D": return UInt32(kVK_ANSI_D)
        case "E": return UInt32(kVK_ANSI_E)
        case "F": return UInt32(kVK_ANSI_F)
        case "G": return UInt32(kVK_ANSI_G)
        case "H": return UInt32(kVK_ANSI_H)
        case "I": return UInt32(kVK_ANSI_I)
        case "J": return UInt32(kVK_ANSI_J)
        case "K": return UInt32(kVK_ANSI_K)
        case "L": return UInt32(kVK_ANSI_L)
        case "M": return UInt32(kVK_ANSI_M)
        case "N": return UInt32(kVK_ANSI_N)
        case "O": return UInt32(kVK_ANSI_O)
        case "P": return UInt32(kVK_ANSI_P)
        case "Q": return UInt32(kVK_ANSI_Q)
        case "R": return UInt32(kVK_ANSI_R)
        case "S": return UInt32(kVK_ANSI_S)
        case "T": return UInt32(kVK_ANSI_T)
        case "U": return UInt32(kVK_ANSI_U)
        case "V": return UInt32(kVK_ANSI_V)
        case "W": return UInt32(kVK_ANSI_W)
        case "X": return UInt32(kVK_ANSI_X)
        case "Y": return UInt32(kVK_ANSI_Y)
        case "Z": return UInt32(kVK_ANSI_Z)
        default: return nil
        }
    }

    private static func digitKeyCode(_ c: Character) -> UInt32? {
        switch c {
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        default: return nil
        }
    }

    private static let miscKeyCodes: [String: UInt32] = [
        "F1": UInt32(kVK_F1), "F2": UInt32(kVK_F2), "F3": UInt32(kVK_F3),
        "F4": UInt32(kVK_F4), "F5": UInt32(kVK_F5), "F6": UInt32(kVK_F6),
        "F7": UInt32(kVK_F7), "F8": UInt32(kVK_F8), "F9": UInt32(kVK_F9),
        "F10": UInt32(kVK_F10), "F11": UInt32(kVK_F11), "F12": UInt32(kVK_F12),
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

    /// AppKit virtual key code → global-hotkey-style name. Used when the
    /// settings panel is in "record next combo" mode.
    static func nameFromKeyCode(_ kc: UInt16) -> String? {
        if let name = Self.invertedMisc[UInt32(kc)] { return name }
        if let letter = Self.invertedLetter[UInt32(kc)] {
            return "Key\(letter)"
        }
        if let digit = Self.invertedDigit[UInt32(kc)] {
            return "Digit\(digit)"
        }
        return nil
    }

    private static let invertedLetter: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z"
    ]

    private static let invertedDigit: [UInt32: String] = [
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9"
    ]

    private static let invertedMisc: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Return): "Enter",
        UInt32(kVK_Escape): "Escape",
        UInt32(kVK_Delete): "Backspace",
        UInt32(kVK_ForwardDelete): "Delete",
        UInt32(kVK_UpArrow): "ArrowUp",
        UInt32(kVK_DownArrow): "ArrowDown",
        UInt32(kVK_LeftArrow): "ArrowLeft",
        UInt32(kVK_RightArrow): "ArrowRight"
    ]

    /// AppKit modifier flags → spec components, in canonical order
    /// (Ctrl+Cmd+Alt+Shift). Used by the settings panel when the user
    /// records a new combo.
    static func modifiersToSpec(_ flags: NSEvent.ModifierFlags) -> [String] {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.command) { parts.append("Cmd") }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }
        return parts
    }
}
