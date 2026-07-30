import Cocoa
import Foundation
import IMECore

// MARK: - 配置存储

/// 配置存储：持有当前配置，负责首次自动创建、加载、保存、重载。
///
/// 主线程专用：所有调用方（菜单操作、应用切换处理、注释模式）都运行在主线程，
/// 因此 `config` 不需要额外同步。原来散落在各处的全局 `var config` 和自由函数
/// 统一收敛到这里，通过 init 注入给各使用方。
final class ConfigStore {
    /// 配置文件路径
    static var path: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/ime-switcher/config.json")
    }

    /// 当前配置（只读；修改请用 `update`，会自动保存）
    private(set) var config: Config

    init() {
        ConfigStore.autoCreateConfigIfNeeded()
        // 解析失败时暂用空配置（loadFromDisk 已弹窗提示原因）
        config = ConfigStore.loadFromDisk() ?? Config(rules: [:], defaultInputSource: nil)
    }

    /// 从磁盘重新加载配置。解析失败时保留当前配置，返回 false。
    @discardableResult
    func reload() -> Bool {
        guard let newConfig = ConfigStore.loadFromDisk() else {
            print("🔄 配置解析失败，保留当前配置")
            return false
        }
        config = newConfig
        print("🔄 配置已重新加载")
        return true
    }

    /// 修改配置并立即保存到磁盘
    func update(_ mutate: (inout Config) -> Void) {
        mutate(&config)
        save()
    }

    /// 保存当前配置到磁盘
    func save() {
        let path = ConfigStore.path
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

    // MARK: - 加载与首次自动创建

    /// 读取并解析配置文件。解析失败时弹窗提示并返回 nil（调用方决定回退策略：
    /// 首次启动用空配置，重新加载时保留当前配置）。
    private static func loadFromDisk() -> Config? {
        let path = self.path

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
    private static func showConfigErrorAlert(path: String, detail: String) {
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

    /// 自动检测输入法并创建默认配置文件（首次运行调用；已存在则跳过）
    private static func autoCreateConfigIfNeeded() {
        let path = self.path
        let fm = FileManager.default

        // 防止重复调用：如果已经存在配置文件则跳过
        guard !fm.fileExists(atPath: path) else { return }

        print("📝 首次使用，正在自动配置...")

        // 检测系统中可用的输入法
        let sources = InputSourceManager.selectableInputSources()
        let hasChinese = sources.contains(where: { $0.id.contains("SCIM") })

        // 优先选用 ABC 作为英文输入法，否则用第一个英文布局
        var englishID = "com.apple.keylayout.ABC"
        for src in sources {
            if src.id == "com.apple.keylayout.ABC" || src.id == "com.apple.keylayout.US" {
                englishID = src.id
                break
            }
        }
        let englishName = inputSourceNameLocal(forID: englishID, in: sources)

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
        let chineseName = chineseID.map { inputSourceNameLocal(forID: $0, in: sources) }

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

        let dir = (path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(defaultConfig)
            try data.write(to: URL(fileURLWithPath: path))
            print("💾 配置已保存: \(path)")
        } catch {
            print("⚠️ 保存配置失败: \(error)")
        }
    }

    /// 从已获取的输入法列表中取本地化名称（autoCreate 时避免重复枚举 TIS 列表）
    private static func inputSourceNameLocal(forID id: String, in sources: [(id: String, name: String)]) -> String {
        sources.first(where: { $0.id == id })?.name ?? id
    }
}
