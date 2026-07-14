import Cocoa
import Carbon

// 禁用 stdout 缓冲，确保日志实时可见
setbuf(stdout, nil)

// MARK: - 配置结构

struct Config: Codable {
    // bundleID -> 输入法 ID,例如 "com.apple.Terminal": "com.apple.keylayout.ABC"
    var rules: [String: String]
    // 没有匹配规则时切到的默认输入法(可选,不填则保持不变)
    var defaultInputSource: String?
}

func configPath() -> String {
    (NSHomeDirectory() as NSString).appendingPathComponent(".config/ime-switcher/config.json")
}

func loadConfig() -> Config {
    let path = configPath()
    guard let data = FileManager.default.contents(atPath: path) else {
        print("⚠️ 未找到配置文件: \(path)")
        print("   请先创建配置文件,参考 config.example.json")
        return Config(rules: [:], defaultInputSource: nil)
    }
    do {
        return try JSONDecoder().decode(Config.self, from: data)
    } catch {
        print("⚠️ 配置文件解析失败: \(error)")
        return Config(rules: [:], defaultInputSource: nil)
    }
}

// MARK: - 输入法切换 (Carbon TIS API)

func findInputSource(withID id: String) -> TISInputSource? {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
        return nil
    }
    for source in list {
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if sourceID == id {
                return source
            }
        }
    }
    return nil
}

func selectInputSource(id: String) {
    guard let source = findInputSource(withID: id) else {
        print("⚠️ 找不到输入法: \(id) (用 list_input_sources 工具查看可用 ID)")
        return
    }
    let result = TISSelectInputSource(source)
    if result == noErr {
        print("✅ 已切换到: \(id)")
    } else {
        print("⚠️ 切换失败,错误码 \(result)")
    }
}

// MARK: - 主逻辑:监听前台应用变化

let config = loadConfig()

/// 获取当前实际选中的输入法 ID
func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func handleAppActivation(_ app: NSRunningApplication) {
    guard let bundleID = app.bundleIdentifier else { return }

    let target: String?
    if let ruleTarget = config.rules[bundleID] {
        target = ruleTarget
    } else if let def = config.defaultInputSource {
        target = def
    } else {
        target = nil
    }

    guard let targetID = target else { return }

    // 查询当前实际输入法，避免手动切换后误跳过
    if targetID == currentInputSourceID() {
        print("⏭️ 当前已是 \(targetID)，跳过切换")
        return
    }

    selectInputSource(id: targetID)
}

let center = NSWorkspace.shared.notificationCenter
center.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { note in
    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        handleAppActivation(app)
    }
}

// 启动时先按当前前台应用切换一次
if let frontApp = NSWorkspace.shared.frontmostApplication {
    handleAppActivation(frontApp)
}

print("🚀 ime-switcher 已启动,正在监听应用切换... (Ctrl+C 退出)")
RunLoop.current.run()
