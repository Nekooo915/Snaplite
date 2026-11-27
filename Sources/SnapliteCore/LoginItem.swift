import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for Launch at Login.
@MainActor
public enum LoginItem {
    public static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
