import Cocoa
import IMECore

// MARK: - 应用切换协调器

/// 应用切换/窗口上下文变化的协调器：把激活事件和窗口上下文翻译成输入法决策。
/// 决策逻辑本身是 IMECore 里的纯函数 `resolveInputSource`，这里只做系统 IO。
/// 所有方法均在主线程调用。
final class AppSwitchHandler {
    private let configStore: ConfigStore
    private let cache: AppKeyboardCache
    private let inputSourceManager: InputSourceManager
    private let windowMonitor: WindowMonitor

    init(
        configStore: ConfigStore,
        cache: AppKeyboardCache,
        inputSourceManager: InputSourceManager,
        windowMonitor: WindowMonitor
    ) {
        self.configStore = configStore
        self.cache = cache
        self.inputSourceManager = inputSourceManager
        self.windowMonitor = windowMonitor
    }

    /// 前台应用切换时调用（NSWorkspace 通知，主线程）
    func handleAppActivation(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }

        // 通知 WindowMonitor 应用切换（它会自行判断是否需要开始/停止轮询）
        windowMonitor.appDidActivate(bundleID: bundleID)

        // 如果该 App 配置了窗口规则，交给 WindowMonitor 异步处理（窗口规则优先）
        if appHasWindowRules(configStore.config, bundleID: bundleID) { return }

        // 未配置窗口规则 → 按原逻辑处理：记忆缓存 → 应用规则 → 默认值
        applyResolution(bundleID: bundleID, context: nil)
    }

    /// 窗口上下文变化时调用（WindowMonitor 回调，主线程）
    func handleWindowContext(bundleID: String, context: WindowContext) {
        applyResolution(bundleID: bundleID, context: context)
    }

    // MARK: - 内部实现

    /// 评估决策并按需切换：窗口规则 > 记忆缓存 → 应用规则 → 默认值
    private func applyResolution(bundleID: String, context: WindowContext?) {
        guard let decision = resolveInputSource(
            config: configStore.config,
            bundleID: bundleID,
            cachedID: cache.inputSource(for: bundleID),
            context: context
        ) else { return }

        if decision.targetID == inputSourceManager.currentInputSourceID() {
            if case .windowRule = decision.reason {
                print("⏭️ 窗口规则命中，但当前已是 \(decision.targetID)")
            }
            return
        }

        if case .windowRule(let pattern) = decision.reason {
            print("🏢 窗口规则命中: 「\(pattern)」→ \(decision.targetID)")
        }
        inputSourceManager.selectInputSource(id: decision.targetID)
    }
}
