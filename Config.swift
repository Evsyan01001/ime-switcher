import Foundation

// MARK: - 配置结构

struct Config: Codable {
    var rules: [String: String]
    var defaultInputSource: String?
    /// 在哪些 App 里 `#` 触发切换到拼音（写中文注释用）
    var hashTriggerApps: [String]? = nil
}

func configPath() -> String {
    (NSHomeDirectory() as NSString).appendingPathComponent(".config/ime-switcher/config.json")
}

func loadConfig() -> Config {
    let path = configPath()
    guard let data = FileManager.default.contents(atPath: path) else {
        print("⚠️ 未找到配置文件: \(path)")
        return Config(rules: [:], defaultInputSource: nil)
    }
    do {
        return try JSONDecoder().decode(Config.self, from: data)
    } catch {
        print("⚠️ 配置文件解析失败: \(error)")
        return Config(rules: [:], defaultInputSource: nil)
    }
}

func saveConfig(_ config: Config) {
    let path = configPath()
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: path))
        print("💾 配置已保存: \(path)")
    } catch {
        print("⚠️ 保存配置失败: \(error)")
    }
}

/// 全局配置实例（首次访问时自动加载）
var config = loadConfig()
