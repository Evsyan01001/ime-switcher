import Cocoa

// MARK: - 窗口上下文变化监控器

/// 监控 Chrome/Ghostty 的窗口/标签页变化，匹配窗口规则后自动切换输入法。
///
/// 工作方式：
/// 1. `appDidActivate(bundleID:)` — 前台应用切换时调用（由 main.swift 触发）
/// 2. 支持的应用持续以 500ms 间隔轮询当前上下文
/// 3. 上下文变化时调用 `evaluateWindowRules(bundleID:context:)` 匹配规则
final class WindowMonitor {
    static let shared = WindowMonitor()

    // MARK: - 上下文获取提供器

    /// 支持的应用及其对应的上下文获取方式
    private let providers: [String: WindowContextProvider] = [
        "com.google.Chrome": ChromeContextProvider(),
        "com.mitchellh.ghostty": GhosttyContextProvider(),
    ]

    // MARK: - 状态

    /// 所有状态操作均在此串行队列上进行，避免竞态
    private let queue = DispatchQueue(label: "com.ime-switcher.window-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var currentBundleID: String?
    private var lastContext: String?

    private init() {}

    // MARK: - 公开接口

    /// 前台应用切换时调用
    /// - Parameter bundleID: 新前台应用的 Bundle ID
    func appDidActivate(bundleID: String) {
        queue.async { [weak self] in
            guard let self else { return }

            if self.providers.keys.contains(bundleID) {
                // 切换到支持的应用 → 开始监控
                self.currentBundleID = bundleID
                self.lastContext = nil
                self._startTimer()
                self._checkNow(bundleID: bundleID)
            } else {
                // 切换到不支持的应用 → 停止监控
                self._stopMonitoring()
            }
        }
    }

    /// 应用即将退出时调用，清理资源
    func stop() {
        queue.async { [weak self] in
            self?._stopMonitoring()
        }
    }

    // MARK: - 内部实现

    private func _startTimer() {
        _stopTimer() // 确保不重复创建
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            guard let self, let bundleID = self.currentBundleID else { return }
            self._checkNow(bundleID: bundleID)
        }
        timer = t
        t.resume()
    }

    private func _stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func _stopMonitoring() {
        _stopTimer()
        currentBundleID = nil
        lastContext = nil
    }

    /// 检查当前上下文是否变化，若变化则评估窗口规则
    private func _checkNow(bundleID: String) {
        guard let provider = providers[bundleID] else { return }

        let context = provider.currentContext()
        guard let ctx = context else {
            // 获取上下文失败（如 Chrome 无窗口），保持上次结果不变
            return
        }

        // 上下文未变化则跳过
        guard ctx != lastContext else { return }

        let prevContext = lastContext
        lastContext = ctx

        // 首次获取上下文（刚切到该应用）或上下文有变化时触发评估
        if prevContext == nil || ctx != prevContext {
            if prevContext == nil {
                print("🌐 [\(bundleID)] 当前上下文: \(ctx.prefix(120))")
            } else {
                print("🌐 [\(bundleID)] 上下文变化: \(prevContext?.prefix(60) ?? "") → \(ctx.prefix(60))")
            }
            DispatchQueue.main.async {
                evaluateWindowRules(bundleID: bundleID, context: ctx)
            }
        }
    }
}
