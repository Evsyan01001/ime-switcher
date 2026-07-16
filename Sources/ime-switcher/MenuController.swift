import Cocoa

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

        // ── 忘记当前 App 的记忆 ──
        if AppKeyboardCache.shared.hasCacheForFrontmostApp {
            let forgetItem = NSMenuItem(
                title: "忘记这个 App 的偏好",
                action: #selector(forgetAppPreference),
                keyEquivalent: ""
            )
            forgetItem.target = self
            menu.addItem(forgetItem)
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

    @objc private func setRuleForCurrentApp(_ sender: NSMenuItem) {
        guard let (bundleID, imeID) = sender.representedObject as? (String, String) else { return }
        config.rules[bundleID] = imeID
        saveConfig(config)
        selectInputSource(id: imeID)
    }

    @objc private func reloadConfigAction() {
        config = loadConfig()
        print("🔄 配置已重新加载")
    }

    @objc private func forgetAppPreference() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        AppKeyboardCache.shared.remove(bundleID: bundleID)
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
        config.hashTriggerKey = String(first)
        saveConfig(config)
        print("🔤 触发键已设为: \(String(first))")
    }

    @objc private func toggleHashTrigger() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }

        var apps = config.hashTriggerApps ?? []
        if let idx = apps.firstIndex(of: bundleID) {
            apps.remove(at: idx)
            print("💬 注释模式已关闭：\(bundleID)")
        } else {
            apps.append(bundleID)
            print("💬 注释模式已开启：\(bundleID)")
        }
        config.hashTriggerApps = apps
        saveConfig(config)
    }

    @objc private func editConfig() {
        let path = configPath()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
