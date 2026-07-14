import Cocoa

setbuf(stdout, nil)

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
