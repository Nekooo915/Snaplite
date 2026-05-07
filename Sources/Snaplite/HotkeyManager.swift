import AppKit
import Carbon.HIToolbox

/// Thin Swift wrapper around `RegisterEventHotKey` from Carbon. We keep
/// state in a manager so re-registering is cheap and unregistration on
/// quit is reliable.
final class HotkeyManager {
    /// Logical slot. Each slot holds at most one binding at a time; binding
    /// it again replaces the previous registration in place.
    enum Slot: UInt32 { case region = 1, window = 2 }

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x534E_4150  // 'SNAP'

    /// Register a binding for a slot. If the slot already has a binding,
    /// the old one is unregistered first. Returns true if the new binding
    /// was accepted by the OS.
    @discardableResult
    func bind(_ slot: Slot, spec: String, action: @escaping () -> Void) -> Bool {
        unbind(slot)

        guard let parsed = HotkeyParser.parse(spec) else {
            NSLog("[snaplite] hotkey: failed to parse spec '\(spec)'")
            return false
        }

        installHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        let status = RegisterEventHotKey(
            parsed.keyCode,
            parsed.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let ref = hotKeyRef else {
            NSLog("[snaplite] hotkey: RegisterEventHotKey failed (\(status)) for '\(spec)'")
            return false
        }
        registrations[slot.rawValue] = Registration(ref: ref, action: action)
        return true
    }

    func unbind(_ slot: Slot) {
        guard let reg = registrations.removeValue(forKey: slot.rawValue) else { return }
        UnregisterEventHotKey(reg.ref)
    }

    func unbindAll() {
        for (_, reg) in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
    }

    // MARK: - Carbon event handler

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let trampoline: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
            guard let event = eventRef, let userData = userData else {
                return OSStatus(eventNotHandledErr)
            }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            // The Carbon handler may be invoked off the main thread; bounce
            // any user-visible work back via DispatchQueue.main.
            if let action = mgr.registrations[hotKeyID.id]?.action {
                DispatchQueue.main.async(execute: action)
            }
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            trampoline,
            1,
            &spec,
            context,
            nil
        )
        handlerInstalled = true
    }

    deinit { unbindAll() }
}
