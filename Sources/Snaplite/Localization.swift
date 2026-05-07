import Foundation

/// Resolved UI language. `Language.auto` is collapsed to one of these two
/// values via `resolve(_:)`.
enum Lang { case en, zh }

enum Localization {
    static func resolve(_ setting: Language) -> Lang {
        switch setting {
        case .en: return .en
        case .zh: return .zh
        case .auto: return detectSystem()
        }
    }

    /// Pick the first preferred localization that we have a translation
    /// for. Anything starting with `zh` (zh-Hans, zh-CN, zh-TW, …) maps to
    /// Chinese; everything else falls back to English.
    private static func detectSystem() -> Lang {
        let preferred = Locale.preferredLanguages
            .first?
            .lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .zh : .en
    }
}

/// Static UI string table. Keeping this struct-of-strings rather than a
/// `Localizable.strings` lookup means we get type-checked references and
/// can ship without a strings bundle entirely.
struct Strings {
    // Panel
    let heading: String
    let saveDestination: String
    let saveToFile: String
    let copyToClipboard: String
    let saveFolder: String
    let choose: String
    let open: String
    let appearance: String
    let showMenubarIcon: String
    let menubarHiddenHint: String
    let language: String
    let languageAuto: String
    let languageEnglish: String
    let languageChinese: String
    let hotkeysSection: String
    let hotkeyCaptureRegion: String
    let hotkeyCaptureWindow: String
    let hotkeyChange: String
    let hotkeyCancel: String
    let hotkeyPressKeys: String
    let hotkeyConflict: String
    let hotkeyInvalid: String

    // Tray
    let menuSettings: String
    let menuCaptureRegion: String
    let menuCaptureWindow: String
    let menuQuit: String
}

extension Strings {
    static func table(for lang: Lang) -> Strings {
        switch lang {
        case .en: return en
        case .zh: return zh
        }
    }

    static let en = Strings(
        heading: "Snaplite",
        saveDestination: "Save destination",
        saveToFile: "Save to file",
        copyToClipboard: "Copy to clipboard",
        saveFolder: "Save folder",
        choose: "Choose…",
        open: "Open",
        appearance: "Appearance",
        showMenubarIcon: "Show menubar icon",
        menubarHiddenHint:
            "With the menubar icon hidden, Snaplite is reachable via global hotkeys, or by relaunching the app to open settings.",
        language: "Language",
        languageAuto: "Auto",
        languageEnglish: "English",
        languageChinese: "简体中文",
        hotkeysSection: "Hotkeys",
        hotkeyCaptureRegion: "Capture region",
        hotkeyCaptureWindow: "Capture window",
        hotkeyChange: "Change",
        hotkeyCancel: "Cancel",
        hotkeyPressKeys: "Press keys… (Esc to cancel)",
        hotkeyConflict: "Both hotkeys are bound to the same combination.",
        hotkeyInvalid: "Invalid combination — try again.",

        menuSettings: "Settings…",
        menuCaptureRegion: "Capture Region",
        menuCaptureWindow: "Capture Window",
        menuQuit: "Quit Snaplite"
    )

    static let zh = Strings(
        heading: "Snaplite",
        saveDestination: "保存方式",
        saveToFile: "保存为文件",
        copyToClipboard: "复制到剪贴板",
        saveFolder: "保存目录",
        choose: "选择…",
        open: "打开",
        appearance: "外观",
        showMenubarIcon: "显示菜单栏图标",
        menubarHiddenHint: "隐藏菜单栏图标后，可通过全局快捷键或重新打开 .app 来进入设置。",
        language: "语言",
        languageAuto: "跟随系统",
        languageEnglish: "English",
        languageChinese: "简体中文",
        hotkeysSection: "快捷键",
        hotkeyCaptureRegion: "区域截图",
        hotkeyCaptureWindow: "窗口截图",
        hotkeyChange: "修改",
        hotkeyCancel: "取消",
        hotkeyPressKeys: "按下组合键…（Esc 取消）",
        hotkeyConflict: "两个快捷键不能绑定到同一组合。",
        hotkeyInvalid: "无效的组合，请重试。",

        menuSettings: "设置…",
        menuCaptureRegion: "区域截图",
        menuCaptureWindow: "窗口截图",
        menuQuit: "退出 Snaplite"
    )
}
