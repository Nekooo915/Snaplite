import Foundation

/// Type-safe localized UI strings resolved from macOS per-app localization (`en` / `zh-Hans`).
/// Contains only crisp labels, button titles, short status badges, and concise error strings.
public struct Strings: Equatable, Sendable {
    // Header
    public let appTitle: String
    public let versionPrefix: String

    // Permission pill & card
    public let permissionTitle: String
    public let permissionStatusGranted: String
    public let permissionStatusRequired: String
    public let permissionRequired: String
    public let openSystemSettings: String
    public let relaunch: String

    // Sections
    public let sectionHotkey: String
    public let sectionAfterCapture: String
    public let sectionGeneral: String

    // Rows & Controls
    public let captureArea: String
    public let outputCopy: String
    public let outputSave: String
    public let outputBoth: String
    public let saveFolder: String
    public let change: String
    public let open: String
    public let showMenubarIcon: String
    public let launchAtLogin: String
    public let completionBanner: String
    public let quitSnaplite: String

    // Hotkey recorder
    public let pressShortcut: String
    public let cancelKey: String
    public let resetToDefault: String
    public let hotkeyErrorMissingModifier: String
    public let hotkeyErrorReserved: String
    public let hotkeyErrorInUse: String
    public let hotkeyErrorUnsupported: String

    // Menu bar
    public let menuCaptureArea: String
    public let menuOpenFolder: String
    public let menuSettings: String
    public let menuQuit: String
    public let menuPermissionRequired: String

    // Completion banner & errors
    public let toastCopied: String
    public let toastSaved: String
    public let toastCopiedAndSaved: String
    public let errorSaveFolderUnavailable: String
    public let errorLoginItemFailed: String
    public let errorCaptureFailed: String

    /// Resolves the localized string table from `preferredLocalization` (defaulting to
    /// `Bundle.main.preferredLocalizations.first`).
    public static func current(preferredLocalization: String? = nil) -> Strings {
        let lang = (preferredLocalization ?? Bundle.main.preferredLocalizations.first ?? "en")
            .lowercased()
        return lang.hasPrefix("zh") ? .zhHans : .en
    }

    public static let en = Strings(
        appTitle: "Snaplite",
        versionPrefix: "v",
        permissionTitle: "Screen Recording",
        permissionStatusGranted: "Granted",
        permissionStatusRequired: "Required",
        permissionRequired: "Screen Recording Required",
        openSystemSettings: "Open System Settings",
        relaunch: "Relaunch",
        sectionHotkey: "Hotkey",
        sectionAfterCapture: "After Capture",
        sectionGeneral: "General",
        captureArea: "Capture Area",
        outputCopy: "Copy",
        outputSave: "Save",
        outputBoth: "Copy & Save",
        saveFolder: "Save Folder",
        change: "Change…",
        open: "Open",
        showMenubarIcon: "Show Menubar Icon",
        launchAtLogin: "Launch at Login",
        completionBanner: "Completion Banner",
        quitSnaplite: "Quit Snaplite",
        pressShortcut: "Press shortcut…",
        cancelKey: "Esc",
        resetToDefault: "Reset to Default",
        hotkeyErrorMissingModifier: "Add a modifier key",
        hotkeyErrorReserved: "Reserved by macOS",
        hotkeyErrorInUse: "Already in use",
        hotkeyErrorUnsupported: "Unsupported key",
        menuCaptureArea: "Capture Area",
        menuOpenFolder: "Open Folder",
        menuSettings: "Settings…",
        menuQuit: "Quit Snaplite",
        menuPermissionRequired: "Screen Recording Required…",
        toastCopied: "Copied",
        toastSaved: "Saved",
        toastCopiedAndSaved: "Copied & Saved",
        errorSaveFolderUnavailable: "Save folder unavailable",
        errorLoginItemFailed: "Login item failed",
        errorCaptureFailed: "Capture failed"
    )

    public static let zhHans = Strings(
        appTitle: "Snaplite",
        versionPrefix: "v",
        permissionTitle: "屏幕录制",
        permissionStatusGranted: "已授权",
        permissionStatusRequired: "需要授权",
        permissionRequired: "需要屏幕录制权限",
        openSystemSettings: "打开系统设置",
        relaunch: "重新启动",
        sectionHotkey: "快捷键",
        sectionAfterCapture: "截图后",
        sectionGeneral: "通用",
        captureArea: "区域截图",
        outputCopy: "复制",
        outputSave: "保存",
        outputBoth: "复制并保存",
        saveFolder: "保存目录",
        change: "更改…",
        open: "打开",
        showMenubarIcon: "显示菜单栏图标",
        launchAtLogin: "登录时启动",
        completionBanner: "截图完成提示",
        quitSnaplite: "退出 Snaplite",
        pressShortcut: "按下快捷键…",
        cancelKey: "Esc",
        resetToDefault: "恢复默认",
        hotkeyErrorMissingModifier: "需要修饰键",
        hotkeyErrorReserved: "系统保留快捷键",
        hotkeyErrorInUse: "快捷键已被占用",
        hotkeyErrorUnsupported: "不支持的按键",
        menuCaptureArea: "区域截图",
        menuOpenFolder: "打开截图文件夹",
        menuSettings: "设置…",
        menuQuit: "退出 Snaplite",
        menuPermissionRequired: "需要屏幕录制权限…",
        toastCopied: "已复制",
        toastSaved: "已保存",
        toastCopiedAndSaved: "已复制并保存",
        errorSaveFolderUnavailable: "保存目录不可用",
        errorLoginItemFailed: "登录项设置失败",
        errorCaptureFailed: "截图失败"
    )
}
