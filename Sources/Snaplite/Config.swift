import Foundation

/// User language preference. `auto` resolves to the OS's first preferred
/// localization (`en` / `zh`) at runtime.
enum Language: String, Codable, CaseIterable {
    case auto, en, zh
}

/// All persistent settings, mirrored 1:1 with the Rust build's TOML model.
/// Stored as JSON in Application Support so Codable handles it natively.
struct Config: Codable, Equatable {
    var saveToFile: Bool
    var copyToClipboard: Bool
    var saveDir: String          // absolute path
    var showTrayIcon: Bool
    var language: Language
    var hotkeyRegion: String     // global-hotkey-style spec, e.g. "Alt+KeyA"
    var hotkeyWindow: String

    static let defaults = Config(
        saveToFile: true,
        copyToClipboard: true,
        saveDir: Self.defaultSaveDir().path,
        showTrayIcon: true,
        language: .auto,
        hotkeyRegion: "Alt+KeyA",
        hotkeyWindow: "Alt+KeyS"
    )

    /// Custom decoder so newly-added fields don't break older config.json
    /// files: any key missing from the JSON falls back to its `defaults`
    /// value instead of failing the whole decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        saveToFile = (try? c.decode(Bool.self, forKey: .saveToFile)) ?? d.saveToFile
        copyToClipboard = (try? c.decode(Bool.self, forKey: .copyToClipboard)) ?? d.copyToClipboard
        saveDir = (try? c.decode(String.self, forKey: .saveDir)) ?? d.saveDir
        showTrayIcon = (try? c.decode(Bool.self, forKey: .showTrayIcon)) ?? d.showTrayIcon
        language = (try? c.decode(Language.self, forKey: .language)) ?? d.language
        hotkeyRegion = (try? c.decode(String.self, forKey: .hotkeyRegion)) ?? d.hotkeyRegion
        hotkeyWindow = (try? c.decode(String.self, forKey: .hotkeyWindow)) ?? d.hotkeyWindow
    }

    init(
        saveToFile: Bool, copyToClipboard: Bool, saveDir: String,
        showTrayIcon: Bool, language: Language,
        hotkeyRegion: String, hotkeyWindow: String
    ) {
        self.saveToFile = saveToFile
        self.copyToClipboard = copyToClipboard
        self.saveDir = saveDir
        self.showTrayIcon = showTrayIcon
        self.language = language
        self.hotkeyRegion = hotkeyRegion
        self.hotkeyWindow = hotkeyWindow
    }

    /// Best-effort load. On any error we silently fall back to defaults so
    /// a corrupt config never blocks startup.
    static func load() -> Config {
        let url = configFileURL()
        guard
            let data = try? Data(contentsOf: url),
            let cfg = try? JSONDecoder().decode(Config.self, from: data)
        else {
            return .defaults
        }
        return cfg
    }

    func save() throws {
        let url = Self.configFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Paths

    static func configFileURL() -> URL {
        applicationSupportDir().appendingPathComponent("config.json")
    }

    static func applicationSupportDir() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Snaplite", isDirectory: true)
    }

    static func defaultSaveDir() -> URL {
        FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Snaplite", isDirectory: true)
    }
}
