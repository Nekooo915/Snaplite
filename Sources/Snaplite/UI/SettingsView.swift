import AppKit
import SnapliteCore
import SwiftUI

/// Main Settings view rendered on demand inside `SettingsWindow`.
/// Uses `@Observable` + `@Bindable` exclusively (zero `@State` / `@Entry` / `@Animatable`).
struct SettingsView: View {
    let viewModel: SettingsViewModel
    @Bindable var preferences: Preferences
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self._preferences = Bindable(viewModel.preferences)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            if viewModel.isPermissionGranted {
                hotkeySection
            } else {
                PermissionCard(viewModel: viewModel)
            }

            afterCaptureSection
            generalSection
            footerSection
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(width: 400)
        .fixedSize(horizontal: true, vertical: true)
        .background(WindowBackdropView().ignoresSafeArea())
        .animation(
            reduceMotion ? .none : .easeInOut(duration: 0.20),
            value: preferences.outputMode
        )
        .animation(
            reduceMotion ? .none : .easeInOut(duration: 0.22),
            value: viewModel.isPermissionGranted
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: Self.resolvedAppIcon())
                .resizable()
                .interpolation(.high)
                .frame(width: 54, height: 54)
                .padding(.leading, -3)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(viewModel.strings.appTitle)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(viewModel.strings.versionPrefix)\(viewModel.appVersion)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.065),
                        in: Capsule()
                    )
            }

            Spacer(minLength: 6)

            permissionPill
        }
        .padding(.vertical, 2)
    }

    private var permissionPill: some View {
        let granted = viewModel.isPermissionGranted
        return Button {
            viewModel.handlePermissionPillClick()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(granted ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)

                Text(
                    granted
                        ? viewModel.strings.permissionStatusGranted
                        : viewModel.strings.permissionStatusRequired
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .adaptiveGlassCapsule(
                tint: granted ? Color.green.opacity(0.08) : Color.orange.opacity(0.14),
                interactive: true
            )
        }
        .buttonStyle(.plain)
        .help(viewModel.strings.permissionTitle)
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: viewModel.strings.sectionHotkey)

            SectionCard {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(viewModel.strings.captureArea)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        HotkeyRecorder(viewModel: viewModel)
                    }

                    if let error = viewModel.hotkeyError {
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
    }

    // MARK: - After Capture

    private var afterCaptureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: viewModel.strings.sectionAfterCapture)

            SectionCard {
                VStack(spacing: 0) {
                    FullWidthSegmentedPicker(
                        options: [
                            (.copy, viewModel.strings.outputCopy),
                            (.save, viewModel.strings.outputSave),
                            (.both, viewModel.strings.outputBoth)
                        ],
                        selection: $preferences.outputMode
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if preferences.outputMode != .copy {
                        CardDivider()
                        saveFolderRow
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .move(edge: .top))
                            )
                    }
                }
            }
        }
    }

    private var saveFolderRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)

                Text(preferences.displaySaveDir)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(preferences.saveDir)

                Button(viewModel.strings.change) {
                    viewModel.chooseSaveFolder()
                }
                .adaptiveGlassButtonStyle(prominent: false)
                .controlSize(.small)

                Button(viewModel.strings.open) {
                    viewModel.openSaveFolder()
                }
                .adaptiveGlassButtonStyle(prominent: false)
                .controlSize(.small)
            }

            if let error = viewModel.folderError {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if viewModel.isDropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                    }
                    .padding(3)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.handleFolderDrop(urls: urls)
        } isTargeted: { targeted in
            viewModel.isDropTargeted = targeted
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: viewModel.strings.sectionGeneral)

            SectionCard {
                VStack(spacing: 0) {
                    toggleRow(
                        title: viewModel.strings.showMenubarIcon,
                        isOn: $preferences.showTrayIcon
                    )

                    CardDivider()

                    VStack(alignment: .leading, spacing: 4) {
                        toggleRow(
                            title: viewModel.strings.launchAtLogin,
                            isOn: Binding(
                                get: { viewModel.launchAtLogin },
                                set: { viewModel.setLaunchAtLogin($0) }
                            )
                        )

                        if let error = viewModel.loginItemError {
                            Text(error)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)
                                .transition(.opacity)
                        }
                    }

                    CardDivider()

                    toggleRow(
                        title: viewModel.strings.completionBanner,
                        isOn: $preferences.showToast
                    )
                }
            }
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9.5)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Spacer()

            Button(viewModel.strings.quitSnaplite) {
                viewModel.quit()
            }
            .adaptiveGlassButtonStyle(prominent: false)
            .controlSize(.regular)
        }
        .padding(.top, 2)
    }

    // MARK: - App Icon Helper

    private static func resolvedAppIcon() -> NSImage {
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            return appIcon
        }
        return NSApp.applicationIconImage
    }
}
