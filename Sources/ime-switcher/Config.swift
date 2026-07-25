import Cocoa
import Foundation
import IMECore

// MARK: - 配置文件路径

func configPath() -> String {
    (NSHomeDirectory() as NSString).appendingPathComponent(".config/ime-switcher/config.json")
}

/// 自动检测输入法并创建默认配置文件（首次运行调用）
func autoCreateConfig() {
    let path = configPath()
    let fm = FileManager.default

    // 防止重复调用：如果已经存在配置文件则跳过
    guard !fm.fileExists(atPath: path) else { return }

    print("📝 首次使用，正在自动配置...")

    // 检测系统中可用的输入法
    let sources = selectableInputSources()
    let hasChinese = sources.contains(where: { $0.id.contains("SCIM") })

    // 优先选用 ABC 作为英文输入法，否则用第一个英文布局
    var englishID = "com.apple.keylayout.ABC"
    for src in sources {
        if src.id == "com.apple.keylayout.ABC" || src.id == "com.apple.keylayout.US" {
            englishID = src.id
            break
        }
    }
    let englishName = inputSourceName(forID: englishID) ?? englishID

    // 优先选用系统拼音作为中文输入法
    var chineseID: String? = nil
    for src in sources {
        if src.id == "com.apple.inputmethod.SCIM.ITABC" {
            chineseID = src.id
            break
        }
    }
    if chineseID == nil {
        for src in sources {
            if src.id.contains("SCIM") {
                chineseID = src.id
                break
            }
        }
    }
    let chineseName = chineseID.flatMap { inputSourceName(forID: $0) }

    // 打印检测结果
    print("📋 检测到输入法: 英文 → \(englishName)", terminator: "")
    if hasChinese, let chineseName {
        print("，中文 → \(chineseName)")
    } else {
        print("（未检测到中文输入法，跳过中文规则）")
    }

    // 构建默认规则
    var rules: [String: String] = [:]
    rules["com.apple.Terminal"] = englishID
    rules["com.apple.dt.Xcode"] = englishID
    rules["com.microsoft.VSCode"] = englishID
    rules["com.googlecode.iterm2"] = englishID

    if let chineseID, hasChinese {
        rules["com.tencent.xinWeChat"] = chineseID
        rules["com.apple.mobilemail"] = chineseID
        rules["com.apple.Notes"] = chineseID
    }

    let defaultConfig = Config(
        rules: rules,
        defaultInputSource: nil,
        hashTriggerApps: ["com.apple.Terminal", "com.microsoft.VSCode", "com.googlecode.iterm2"],
        hashTriggerKey: "#",
        hashTriggerChineseSource: chineseID,
        hashTriggerEnglishSource: englishID
    )

    print("📄 已生成默认配置（\(rules.count) 条规则）")
    print("💡 如需调整：点击菜单栏 ⌨ 图标 → 编辑配置文件")
    saveConfig(defaultConfig)
}

/// 读取并解析配置文件。解析失败时弹窗提示并返回 nil（调用方决定回退策略：
/// 首次启动用空配置，重新加载时保留当前配置）。
func loadConfig() -> Config? {
    let path = configPath()

    // 首次运行：自动创建配置文件
    autoCreateConfig()

    guard let data = FileManager.default.contents(atPath: path) else {
        print("⚠️ 无法读取配置文件: \(path)")
        showConfigErrorAlert(path: path, detail: "文件不存在或无法读取")
        return nil
    }
    do {
        return try JSONDecoder().decode(Config.self, from: data)
    } catch {
        print("⚠️ 配置文件解析失败: \(error)")
        showConfigErrorAlert(path: path, detail: error.localizedDescription)
        return nil
    }
}

/// 配置出错时弹窗提示（避免 JSON 笔误导致规则静默失效）
private func showConfigErrorAlert(path: String, detail: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "ime-switcher 配置文件解析失败"
    alert.informativeText = "\(path)\n\n\(detail)\n\n修复后可通过菜单栏 ⌨ →「重新加载配置」恢复。"
    alert.addButton(withTitle: "打开配置文件")
    alert.addButton(withTitle: "继续")
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
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

/// 全局配置实例（首次访问时自动加载；解析失败时暂用空配置）
var config = loadConfig() ?? Config(rules: [:], defaultInputSource: nil)
