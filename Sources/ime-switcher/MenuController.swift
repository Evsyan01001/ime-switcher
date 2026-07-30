import Cocoa
import IMECore

// MARK: - 菜单栏控制器

class MenuController: NSObject, NSMenuDelegate {
    private let configStore: ConfigStore
    private let cache: AppKeyboardCache
    private let windowMonitor: WindowMonitor
    private let inputSourceManager: InputSourceManager

    private let statusItem: NSStatusItem

    /// 读取当前配置的便捷访问（修改请用 configStore.update）
    private var config: Config { configStore.config }

    init(
        configStore: ConfigStore,
        cache: AppKeyboardCache,
        windowMonitor: WindowMonitor,
        inputSourceManager: InputSourceManager
    ) {
        self.configStore = configStore
        self.cache = cache
        self.windowMonitor = windowMonitor
        self.inputSourceManager = inputSourceManager

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // 自定义菜单栏图标，标记为模板图像以自动适配深色/浅色菜单栏
            if let iconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
               let image = NSImage(contentsOf: iconURL) {
                image.isTemplate = true
                button.image = image
            } else {
                button.image = NSImage(
                    systemSymbolName: "keyboard",
                    accessibilityDescription: "IME Switcher"
                )
            }
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
            let sources = InputSourceManager.selectableInputSources()

            if sources.isEmpty {
                let noItem = NSMenuItem(title: "(无可用输入法)", action: nil, keyEquivalent: "")
                noItem.isEnabled = false
                submenu.addItem(noItem)
            } else {
                for (id, name) in sources {
                    let item = NSMenuItem(title: name, action: #selector(setRuleForCurrentApp(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = (bundleID, id)
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

        // ── 浏览器页面规则：当前网站 / 当前页面 ──
        // 前台是支持窗口规则的浏览器时，直接把当前 URL 生成 windowRules，无需手编配置
        if let (bundleID, ctx) = windowMonitor.contextForFrontmostApp(),
           let url = ctx.url {
            if let host = URL(string: url)?.host, !host.isEmpty {
                let hostPattern = host.replacingOccurrences(of: ".", with: "\\.")
                addPageRuleSubmenu(
                    to: menu,
                    title: "将当前网站（\(host)）设为",
                    bundleID: bundleID,
                    pattern: hostPattern
                )
            }
            addPageRuleSubmenu(
                to: menu,
                title: "将当前页面设为",
                bundleID: bundleID,
                pattern: NSRegularExpression.escapedPattern(for: url)
            )
        }

        menu.addItem(.separator())

        // ── Ghostty 进程规则：当前进程 ──
        if let (bundleID, ctx) = windowMonitor.contextForFrontmostApp(),
           bundleID == "com.mitchellh.ghostty" {
            for procName in ctx.processes {
                addProcessRuleSubmenu(
                    to: menu,
                    title: "将当前进程「\(procName)」设为",
                    bundleID: bundleID,
                    procName: procName
                )
            }
            if let title = ctx.title {
                addPageRuleSubmenu(
                    to: menu,
                    title: "将当前标签页设为",
                    bundleID: bundleID,
                    pattern: NSRegularExpression.escapedPattern(for: title)
                )
            }
        }

        // ── 注释模式 ──
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleID = app.bundleIdentifier,
           let appName = app.localizedName {

            let parentItem = NSMenuItem(title: "💬 注释模式", action: nil, keyEquivalent: "")
            let submenu = NSMenu()

            // 触发键显示
            let triggerKey = config.hashTriggerKey ?? "#"
            let keyItem = NSMenuItem(title: "触发键: \(triggerKey)", action: nil, keyEquivalent: "")
            keyItem.isEnabled = false
            submenu.addItem(keyItem)

            // 自定义触发键
            let customItem = NSMenuItem(title: "自定义触发键...", action: #selector(customizeTriggerKey), keyEquivalent: "")
            customItem.target = self
            submenu.addItem(customItem)

            submenu.addItem(.separator())

            // 当前 App 开关
            let isOn = (config.hashTriggerApps ?? []).contains(bundleID)
            let toggleItem = NSMenuItem(
                title: "注释模式：\(appName)",
                action: #selector(toggleHashTrigger),
                keyEquivalent: ""
            )
            toggleItem.target = self
            toggleItem.state = isOn ? .on : .off
            submenu.addItem(toggleItem)

            menu.setSubmenu(submenu, for: parentItem)
            menu.addItem(parentItem)
        }

        // ── 输入法记忆 ──
        var addedCacheItems = false
        if cache.hasCacheForFrontmostApp {
            let forgetItem = NSMenuItem(
                title: "忘记这个 App 的偏好",
                action: #selector(forgetAppPreference),
                keyEquivalent: ""
            )
            forgetItem.target = self
            menu.addItem(forgetItem)
            addedCacheItems = true
        }
        if !cache.isEmpty {
            let clearAllItem = NSMenuItem(
                title: "清除全部记忆",
                action: #selector(clearAllPreferences),
                keyEquivalent: ""
            )
            clearAllItem.target = self
            menu.addItem(clearAllItem)
            addedCacheItems = true
        }
        if addedCacheItems {
            menu.addItem(.separator())
        }

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

    /// 构建「网站/页面 → 输入法」子菜单（选中项打勾表示已有同 pattern 规则）
    private func addPageRuleSubmenu(to menu: NSMenu, title: String, bundleID: String, pattern: String) {
        let parentItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (id, name) in InputSourceManager.selectableInputSources() {
            let item = NSMenuItem(title: name, action: #selector(setWindowRuleForCurrentPage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (bundleID, pattern, id)
            if config.windowRules?.contains(where: {
                $0.bundleID == bundleID && $0.pattern == pattern && $0.inputSource == id
            }) == true {
                item.state = .on
            }
            submenu.addItem(item)
        }
        menu.setSubmenu(submenu, for: parentItem)
        menu.addItem(parentItem)
    }

    @objc private func setWindowRuleForCurrentPage(_ sender: NSMenuItem) {
        guard let (bundleID, pattern, imeID) = sender.representedObject as? (String, String, String) else { return }

        configStore.update { config in
            var rules = config.windowRules ?? []
            // 同 App 同 pattern 的旧规则替换掉，避免重复
            rules.removeAll { $0.bundleID == bundleID && $0.pattern == pattern }
            // 插到最前：菜单设置的精确规则优先于配置文件里的宽泛规则
            rules.insert(WindowRule(bundleID: bundleID, pattern: pattern, inputSource: imeID), at: 0)
            config.windowRules = rules
        }
        inputSourceManager.selectInputSource(id: imeID)
        print("🌐 已添加窗口规则: 「\(pattern)」→ \(imeID)")
    }

    @objc private func setRuleForCurrentApp(_ sender: NSMenuItem) {
        guard let (bundleID, imeID) = sender.representedObject as? (String, String) else { return }
        configStore.update { $0.rules[bundleID] = imeID }
        inputSourceManager.selectInputSource(id: imeID)
    }

    // MARK: - Ghostty 进程规则

    /// 添加「当前进程 → 输入法」子菜单（选中项打勾表示已有同 proc 的规则）
    private func addProcessRuleSubmenu(to menu: NSMenu, title: String, bundleID: String, procName: String) {
        let parentItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let pattern = ghosttyProcPattern(for: procName)
        for (id, name) in InputSourceManager.selectableInputSources() {
            let item = NSMenuItem(title: name, action: #selector(setWindowRuleForCurrentProcess(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = (bundleID, procName, id)
            if config.windowRules?.contains(where: {
                $0.bundleID == bundleID && $0.pattern == pattern && $0.inputSource == id
            }) == true {
                item.state = .on
            }
            submenu.addItem(item)
        }
        menu.setSubmenu(submenu, for: parentItem)
        menu.addItem(parentItem)
    }

    @objc private func setWindowRuleForCurrentProcess(_ sender: NSMenuItem) {
        guard let (bundleID, procName, imeID) = sender.representedObject as? (String, String, String) else { return }

        let pattern = ghosttyProcPattern(for: procName)

        configStore.update { config in
            var rules = config.windowRules ?? []
            // 同 App 同 pattern 的旧规则替换掉，避免重复
            rules.removeAll { $0.bundleID == bundleID && $0.pattern == pattern }
            // 插到最前：菜单设置的精确规则优先于配置文件里的宽泛规则
            rules.insert(WindowRule(bundleID: bundleID, pattern: pattern, inputSource: imeID), at: 0)
            config.windowRules = rules
        }
        inputSourceManager.selectInputSource(id: imeID)
        print("🌐 已添加 Ghostty 进程规则: 「\(procName)」→ \(imeID)")
    }

    /// 生成 Ghostty 进程匹配模式：匹配 proc: 段中独立的进程名
    private func ghosttyProcPattern(for procName: String) -> String {
        // 格式: "title:... | proc:zsh,vim,node"（见 WindowContext.matchString）
        // 用 \b 词边界确保不会部分匹配（如 "vim" 不会匹配 "vimproc"）
        let escaped = NSRegularExpression.escapedPattern(for: procName)
        return "proc:.*\\b\(escaped)\\b.*"
    }

    @objc private func reloadConfigAction() {
        // 解析失败时保留当前配置（ConfigStore 已弹窗提示原因）
        configStore.reload()
    }

    @objc private func forgetAppPreference() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        cache.remove(bundleID: bundleID)
    }

    @objc private func clearAllPreferences() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清除全部输入法记忆？"
        alert.informativeText = "所有 App 的手动选择记录将被删除，之后恢复按配置文件规则切换。"
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            cache.removeAll()
        }
    }

    @objc private func customizeTriggerKey() {
        let alert = NSAlert()
        alert.messageText = "自定义触发键"
        alert.informativeText = "输入一个字符作为注释模式的触发键，按该键后自动切换到拼音。"

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        textField.stringValue = config.hashTriggerKey ?? "#"
        textField.placeholderString = "#"
        textField.maximumNumberOfLines = 1
        alert.accessoryView = textField

        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return }
        configStore.update { $0.hashTriggerKey = String(first) }
        print("🔤 触发键已设为: \(String(first))")
    }

    @objc private func toggleHashTrigger() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }

        configStore.update { config in
            var apps = config.hashTriggerApps ?? []
            if let idx = apps.firstIndex(of: bundleID) {
                apps.remove(at: idx)
                print("💬 注释模式已关闭：\(bundleID)")
            } else {
                apps.append(bundleID)
                print("💬 注释模式已开启：\(bundleID)")
            }
            config.hashTriggerApps = apps
        }
    }

    @objc private func editConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: ConfigStore.path))
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
