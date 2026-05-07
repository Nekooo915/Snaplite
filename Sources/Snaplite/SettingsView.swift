import AppKit
import SwiftUI

/// Settings panel — SwiftUI Form bound straight to `AppState.config`.
struct SettingsView: View {
    @ObservedObject var state: AppState

    @State private var recording: HotkeySlot? = nil
    @State private var errorMessage: String? = nil
    @State private var keyMonitor: Any? = nil

    private enum HotkeySlot { case region, window }

    private var strings: Strings {
        Strings.table(for: Localization.resolve(state.config.language))
    }

    var body: some View {
        Form {
            saveDestinationSection
            if state.config.saveToFile {
                saveFolderSection
            }
            appearanceSection
            hotkeysSection
            languageSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 480)
        .onChange(of: recording) { newValue in
            updateKeyMonitor(active: newValue != nil)
        }
        .onDisappear { updateKeyMonitor(active: false) }
    }

    // MARK: - Sections

    private var saveDestinationSection: some View {
        Section(strings.saveDestination) {
            Toggle(strings.saveToFile, isOn: Binding(
                get: { state.config.saveToFile },
                set: { newVal in
                    if !newVal && !state.config.copyToClipboard { return }
                    state.config.saveToFile = newVal
                }
            ))
            Toggle(strings.copyToClipboard, isOn: Binding(
                get: { state.config.copyToClipboard },
                set: { newVal in
                    if !newVal && !state.config.saveToFile { return }
                    state.config.copyToClipboard = newVal
                }
            ))
        }
    }

    private var saveFolderSection: some View {
        Section(strings.saveFolder) {
            Text(state.config.saveDir)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            HStack {
                Button(strings.choose) { chooseSaveDir() }
                Button(strings.open) { openInFinder() }
            }
        }
    }

    private var appearanceSection: some View {
        Section(strings.appearance) {
            Toggle(strings.showMenubarIcon, isOn: $state.config.showTrayIcon)
            if !state.config.showTrayIcon {
                Text(strings.menubarHiddenHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hotkeysSection: some View {
        Section(strings.hotkeysSection) {
            hotkeyRow(
                label: strings.hotkeyCaptureRegion,
                slot: .region,
                spec: state.config.hotkeyRegion
            )
            hotkeyRow(
                label: strings.hotkeyCaptureWindow,
                slot: .window,
                spec: state.config.hotkeyWindow
            )
            if let err = errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var languageSection: some View {
        Section(strings.language) {
            Picker("", selection: $state.config.language) {
                Text(strings.languageAuto).tag(Language.auto)
                Text(strings.languageEnglish).tag(Language.en)
                Text(strings.languageChinese).tag(Language.zh)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Hotkey row

    @ViewBuilder
    private func hotkeyRow(label: String, slot: HotkeySlot, spec: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if recording == slot {
                Text(strings.hotkeyPressKeys)
                    .italic()
                    .foregroundStyle(.blue)
                Button(strings.hotkeyCancel) { recording = nil }
            } else {
                Text(HotkeyParser.display(spec))
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 60, alignment: .trailing)
                Button(strings.hotkeyChange) {
                    errorMessage = nil
                    recording = slot
                }
            }
        }
    }

    // MARK: - Folder actions

    private func chooseSaveDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: state.config.saveDir)
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            state.config.saveDir = url.path
            try? FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true
            )
        }
    }

    private func openInFinder() {
        let url = URL(fileURLWithPath: state.config.saveDir, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(url)
    }

    // MARK: - Hotkey recording

    private func updateKeyMonitor(active: Bool) {
        if active && keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleRecordingKey(event)
            }
        } else if !active, let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    /// Returns `nil` to swallow the event so the keystroke doesn't leak
    /// into the panel's text fields, etc.
    private func handleRecordingKey(_ event: NSEvent) -> NSEvent? {
        // Esc cancels.
        if event.keyCode == 0x35 {  // kVK_Escape
            recording = nil
            return nil
        }

        guard
            let slot = recording,
            let codeName = HotkeyParser.nameFromKeyCode(event.keyCode)
        else {
            return nil
        }

        let mods = HotkeyParser.modifiersToSpec(event.modifierFlags)

        // Validity: a non-modifier key + at least one modifier, OR a function
        // key (F1...F12) alone.
        let isFunctionKey = codeName.hasPrefix("F") &&
            codeName.dropFirst().allSatisfy(\.isNumber)
        if mods.isEmpty && !isFunctionKey {
            // Wait for the user to also press a modifier.
            return nil
        }

        var parts = mods
        parts.append(codeName)
        let newSpec = parts.joined(separator: "+")

        guard HotkeyParser.parse(newSpec) != nil else {
            errorMessage = strings.hotkeyInvalid
            recording = nil
            return nil
        }

        // Conflict check.
        let other: String = (slot == .region)
            ? state.config.hotkeyWindow
            : state.config.hotkeyRegion
        if other.caseInsensitiveCompare(newSpec) == .orderedSame {
            errorMessage = strings.hotkeyConflict
            recording = nil
            return nil
        }

        switch slot {
        case .region: state.config.hotkeyRegion = newSpec
        case .window: state.config.hotkeyWindow = newSpec
        }
        errorMessage = nil
        recording = nil
        return nil
    }
}
