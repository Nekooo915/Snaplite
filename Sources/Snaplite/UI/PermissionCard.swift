import SwiftUI

/// Replaces the Hotkey section when Screen Recording permission is missing.
/// Strictly concise: orange shield icon, title, and action buttons with zero descriptive paragraph.
struct PermissionCard: View {
    let viewModel: SettingsViewModel

    var body: some View {
        SectionCard(accentTint: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text(viewModel.strings.permissionRequired)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button(viewModel.strings.openSystemSettings) {
                        viewModel.openSystemSettings()
                    }
                    .adaptiveGlassButtonStyle(prominent: true)
                    .controlSize(.regular)

                    Button(viewModel.strings.relaunch) {
                        viewModel.relaunchApp()
                    }
                    .adaptiveGlassButtonStyle(prominent: false)
                    .controlSize(.regular)

                    Spacer(minLength: 0)
                }
            }
            .padding(14)
        }
    }
}
