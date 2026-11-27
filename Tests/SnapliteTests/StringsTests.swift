import Testing
@testable import SnapliteCore

@Suite("Strings")
struct StringsTests {
    @Test("Resolves English and Simplified Chinese tables from localization codes")
    func localizationResolution() {
        #expect(Strings.current(preferredLocalization: "en") == .en)
        #expect(Strings.current(preferredLocalization: "en-US") == .en)
        #expect(Strings.current(preferredLocalization: "ja") == .en)

        #expect(Strings.current(preferredLocalization: "zh-Hans") == .zhHans)
        #expect(Strings.current(preferredLocalization: "zh-Hans-CN") == .zhHans)
        #expect(Strings.current(preferredLocalization: "zh") == .zhHans)
        #expect(Strings.current(preferredLocalization: "ZH-CN") == .zhHans)
    }

    @Test("Contains crisp labels and localized HotkeyError descriptions")
    func labelsAndErrors() {
        let en = Strings.en
        let zh = Strings.zhHans

        #expect(en.appTitle == "Snaplite")
        #expect(zh.appTitle == "Snaplite")
        #expect(en.sectionHotkey == "Hotkey")
        #expect(zh.sectionHotkey == "快捷键")
        #expect(en.outputBoth == "Copy & Save")
        #expect(zh.outputBoth == "复制并保存")
        #expect(en.toastCopied == "Copied")
        #expect(zh.toastCopied == "已复制")

        #expect(HotkeyError.missingModifier.localizedDescription(using: en) == en.hotkeyErrorMissingModifier)
        #expect(HotkeyError.reservedBySystem.localizedDescription(using: zh) == zh.hotkeyErrorReserved)
        #expect(HotkeyError.registrationFailed(-1).localizedDescription(using: en) == en.hotkeyErrorInUse)
        #expect(HotkeyError.unsupportedKey.localizedDescription(using: zh) == zh.hotkeyErrorUnsupported)
    }
}
