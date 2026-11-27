import SnapliteCore
import SwiftUI

/// Interactive Liquid Glass keycap shortcut recorder with fluid morphing between
/// keycap display and recording capsule states.
struct HotkeyRecorder: View {
    let viewModel: SettingsViewModel
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AdaptiveGlassContainer(spacing: 6) {
            Group {
                if viewModel.isRecordingHotkey {
                    recordingCapsule
                } else {
                    keycapsButton
                }
            }
        }
        .modifier(
            HorizontalShakeEffect(
                animatableData: viewModel.hotkeyShakeTrigger,
                amplitude: reduceMotion ? 0 : 5.5
            )
        )
        .animation(
            reduceMotion ? .easeInOut(duration: 0.14) : .spring(duration: 0.30, bounce: 0.18),
            value: viewModel.isRecordingHotkey
        )
        .animation(
            reduceMotion ? .none : .easeInOut(duration: 0.34),
            value: viewModel.hotkeyShakeTrigger
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.strings.captureArea)
        .accessibilityValue(
            viewModel.isRecordingHotkey
                ? viewModel.strings.pressShortcut
                : HotkeyDisplay.compactString(for: viewModel.preferences.hotkey)
        )
    }

    private var keycapsButton: some View {
        let tokens = HotkeyDisplay.tokens(for: viewModel.preferences.hotkey)
        return Button {
            viewModel.startRecordingHotkey()
        } label: {
            HStack(spacing: 5) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    Text(token)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(minWidth: 28, minHeight: 27)
                        .padding(.horizontal, token.count > 1 ? 8 : 5)
                        .adaptiveGlassKeycap(cornerRadius: 9, interactive: true)
                        .adaptiveGlassEffectID("hotkey-keycap-\(index)", in: glassNamespace)
                        .adaptiveGlassTransition(reduceMotion: reduceMotion)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(viewModel.strings.resetToDefault) {
                viewModel.resetHotkeyToDefault()
            }
            .disabled(viewModel.preferences.hotkey == .default)
        }
    }

    private var recordingCapsule: some View {
        Button {
            viewModel.stopRecordingHotkey()
        } label: {
            HStack(spacing: 7) {
                Text(viewModel.strings.pressShortcut)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                Text(viewModel.strings.cancelKey)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 26)
            .adaptiveGlassCapsule(tint: Color.accentColor.opacity(0.15), interactive: true)
            .adaptiveGlassEffectID("hotkey-keycap-0", in: glassNamespace)
            .adaptiveGlassTransition(reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
    }
}
