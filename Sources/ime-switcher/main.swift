import Cocoa

setbuf(stdout, nil)

// MARK: - 版本

/// 当前版本号（语义化版本，与 git tag 保持一致）
let appVersion = "v1.2"

// MARK: - 服务装配（依赖注入）

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 不显示 Dock 图标，仅菜单栏

// 服务实例：全局状态收敛于此，通过 init 注入到各使用方
let switchTracker = InputSwitchTracker()
let inputSourceManager = InputSourceManager(tracker: switchTracker)
let configStore = ConfigStore()
let keyboardCache = AppKeyboardCache(tracker: switchTracker, inputSourceManager: inputSourceManager)
let windowMonitor = WindowMonitor()
let appSwitchHandler = AppSwitchHandler(
    configStore: configStore,
    cache: keyboardCache,
    inputSourceManager: inputSourceManager,
    windowMonitor: windowMonitor
)
windowMonitor.onContextChange = { [weak appSwitchHandler] bundleID, context in
    appSwitchHandler?.handleWindowContext(bundleID: bundleID, context: context)
}

let menuController = MenuController(
    configStore: configStore,
    cache: keyboardCache,
    windowMonitor: windowMonitor,
    inputSourceManager: inputSourceManager
)

// MARK: - 启动

let center = NSWorkspace.shared.notificationCenter
center.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { note in
    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        appSwitchHandler.handleAppActivation(app)
    }
}

// 启动时按当前前台应用切换一次
if let frontApp = NSWorkspace.shared.frontmostApplication {
    appSwitchHandler.handleAppActivation(frontApp)
}

// # 触发拼音
let hashTrigger = HashTrigger(configStore: configStore, inputSourceManager: inputSourceManager)
hashTrigger.start()

print("🚀 ime-switcher \(appVersion) 已启动,正在监听应用切换...")
app.run()
