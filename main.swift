import Cocoa
import Carbon

// 禁用 stdout 缓冲，确保日志实时可见
setbuf(stdout, nil)

// MARK: - 配置结构

struct Config: Codable {
    var rules: [String: String]
    var defaultInputSource: String?
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
    // 确保目录存在
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

var config = loadConfig()

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
        print("⚠️ 找不到输入法: \(id)")
        return
    }
    let result = TISSelectInputSource(source)
    if result == noErr {
        print("✅ 已切换到: \(id)")
    } else {
        print("⚠️ 切换失败,错误码 \(result)")
    }
}

/// 获取当前实际选中的输入法 ID
func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

/// 获取所有可选的输入法 (ID, 名称) 列表
func selectableInputSources() -> [(id: String, name: String)] {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }
    var results: [(String, String)] = []
    for source in list {
        // 只列出可选择的输入法
        var selectable = false
        if let selPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
            selectable = Unmanaged<CFBoolean>.fromOpaque(selPtr).takeUnretainedValue() == kCFBooleanTrue
        }
        guard selectable else { continue }

        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        var name = id
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
        results.append((id, name))
    }
    return results
}

/// 根据输入法 ID 获取本地化名称
func inputSourceName(forID id: String) -> String? {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
        return nil
    }
    for source in list {
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if sourceID == id {
                if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                    return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                }
            }
        }
    }
    return nil
}

// MARK: - 主逻辑: 监听前台应用变化

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

    if targetID == currentInputSourceID() {
        print("⏭️ 当前已是 \(targetID)，跳过切换")
        return
    }

    selectInputSource(id: targetID)
}

// MARK: - 菜单栏控制器

class MenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "keyboard",
                accessibilityDescription: "IME Switcher"
            )
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: NSMenuDelegate — 每次打开菜单时刷新内容

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        // ── 一键设规则：子菜单列出所有输入法 ──
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleID = app.bundleIdentifier,
           let appName = app.localizedName {

            let parentItem = NSMenuItem(title: "将「\(appName)」设为", action: nil, keyEquivalent: "")
            let submenu = NSMenu()

            // 获取所有可选输入法
            let sources = selectableInputSources()

            if sources.isEmpty {
                let noItem = NSMenuItem(title: "(无可用输入法)", action: nil, keyEquivalent: "")
                noItem.isEnabled = false
                submenu.addItem(noItem)
            } else {
                for (id, name) in sources {
                    let item = NSMenuItem(title: name, action: #selector(setRuleForCurrentApp(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = (bundleID, id)
                    // ✓ 标记已配置的规则
                    if config.rules[bundleID] == id {
                        item.state = .on
                    }
                    submenu.addItem(item)
                }
            }

            menu.setSubmenu(submenu, for: parentItem)
            menu.addItem(parentItem)
        } else {
            let item = NSMenuItem(title: "(无法获取当前应用)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // ── 重新加载配置 ──
        let reloadItem = NSMenuItem(title: "重新加载配置", action: #selector(reloadConfigAction), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        // ── 编辑配置文件 ──
        let editItem = NSMenuItem(title: "编辑配置文件...", action: #selector(editConfig), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())

        // ── 退出 ──
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: Actions

    @objc private func setRuleForCurrentApp(_ sender: NSMenuItem) {
        guard let (bundleID, imeID) = sender.representedObject as? (String, String) else { return }
        config.rules[bundleID] = imeID
        saveConfig(config)
        // 立即应用
        selectInputSource(id: imeID)
    }

    @objc private func reloadConfigAction() {
        config = loadConfig()
        print("🔄 配置已重新加载")
    }

    @objc private func editConfig() {
        let path = configPath()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - 启动

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 不显示 Dock 图标，仅菜单栏

let menuController = MenuController()

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

// 启动时按当前前台应用切换一次
if let frontApp = NSWorkspace.shared.frontmostApplication {
    handleAppActivation(frontApp)
}

print("🚀 ime-switcher 已启动,正在监听应用切换...")
app.run()
