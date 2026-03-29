import Foundation
import Carbon

struct HotkeyConfig: Codable {
    var modifiers: UInt32
    var keyCode: UInt32
    var enabled: Bool

    init(modifiers: UInt32 = UInt32(cmdKey | shiftKey), keyCode: UInt32 = 45, enabled: Bool = true) {
        // Default: Cmd+Shift+N (keyCode 45 = 'N' on macOS)
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.enabled = enabled
    }
}

struct FontConfig: Codable {
    var fontName: String
    var fontSize: Double

    init(fontName: String = "System", fontSize: Double = 13) {
        self.fontName = fontName
        self.fontSize = fontSize
    }
}

struct AppConfig: Codable {
    var dataDirectory: String?
    var toggleHotkey: HotkeyConfig
    var defaultFont: FontConfig

    init(dataDirectory: String? = nil, toggleHotkey: HotkeyConfig = HotkeyConfig(), defaultFont: FontConfig = FontConfig()) {
        self.dataDirectory = dataDirectory
        self.toggleHotkey = toggleHotkey
        self.defaultFont = defaultFont
    }
}

class ConfigService {
    private var config: AppConfig
    private let configPath: String

    static var defaultDataDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PostItNotes").path
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configDir = appSupport.appendingPathComponent("PostItNotes")
        configPath = configDir.appendingPathComponent("config.json").path

        if !FileManager.default.fileExists(atPath: configDir.path) {
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        if FileManager.default.fileExists(atPath: configPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
                config = try JSONDecoder().decode(AppConfig.self, from: data)
            } catch {
                print("Failed to load config: \(error)")
                config = AppConfig()
            }
        } else {
            config = AppConfig()
            save()
        }
    }

    func getDataDirectory() -> String {
        return config.dataDirectory ?? ConfigService.defaultDataDirectory
    }

    func setDataDirectory(_ path: String) {
        config.dataDirectory = path
        save()
    }

    func getHotkeyConfig() -> HotkeyConfig {
        return config.toggleHotkey
    }

    func setHotkeyConfig(_ hotkey: HotkeyConfig) {
        config.toggleHotkey = hotkey
        save()
    }

    func getDefaultFont() -> FontConfig {
        return config.defaultFont
    }

    func setDefaultFont(_ font: FontConfig) {
        config.defaultFont = font
        save()
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(config)
            try data.write(to: URL(fileURLWithPath: configPath))
        } catch {
            print("Failed to save config: \(error)")
        }
    }
}
