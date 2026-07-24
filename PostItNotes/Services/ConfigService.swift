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

enum ViewMode: String, Codable {
    case windows
    case tabs
}

struct WindowFrame: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct AppConfig: Codable {
    var dataDirectory: String?
    var toggleHotkey: HotkeyConfig
    var defaultFont: FontConfig
    var viewMode: ViewMode?
    var tabWindow: WindowFrame?

    init(
        dataDirectory: String? = nil,
        toggleHotkey: HotkeyConfig = HotkeyConfig(),
        defaultFont: FontConfig = FontConfig(),
        viewMode: ViewMode? = nil,
        tabWindow: WindowFrame? = nil
    ) {
        self.dataDirectory = dataDirectory
        self.toggleHotkey = toggleHotkey
        self.defaultFont = defaultFont
        self.viewMode = viewMode
        self.tabWindow = tabWindow
    }

    // Decode every key leniently: a config written by an older (or newer) build
    // must never fail to load, otherwise settings like dataDirectory would be
    // silently reset and the user's notes would look like they vanished.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dataDirectory = (try? container.decodeIfPresent(String.self, forKey: .dataDirectory)) ?? nil
        if let hotkey = try? container.decodeIfPresent(HotkeyConfig.self, forKey: .toggleHotkey) {
            toggleHotkey = hotkey
        } else {
            toggleHotkey = HotkeyConfig()
        }
        if let font = try? container.decodeIfPresent(FontConfig.self, forKey: .defaultFont) {
            defaultFont = font
        } else {
            defaultFont = FontConfig()
        }
        viewMode = (try? container.decodeIfPresent(ViewMode.self, forKey: .viewMode)) ?? nil
        tabWindow = (try? container.decodeIfPresent(WindowFrame.self, forKey: .tabWindow)) ?? nil
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

    func getViewMode() -> ViewMode {
        return config.viewMode ?? .windows
    }

    func setViewMode(_ mode: ViewMode) {
        config.viewMode = mode
        save()
    }

    func getTabWindowFrame() -> WindowFrame? {
        return config.tabWindow
    }

    func setTabWindowFrame(_ frame: WindowFrame) {
        config.tabWindow = frame
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
