import Cocoa

// MARK: - 应用切换逻辑

func handleAppActivation(_ app: NSRunningApplication) {
    guard let bundleID = app.bundleIdentifier else { return }

    // 通知 WindowMonitor 应用切换（它会自行判断是否需要开始/停止轮询）
    WindowMonitor.shared.appDidActivate(bundleID: bundleID)

    // 如果该 App 配置了窗口规则，交给 WindowMonitor 异步处理（窗口规则优先）
    if hasWindowRules(for: bundleID) { return }

    // 未配置窗口规则 → 按原逻辑处理：记忆缓存 → 应用规则 → 默认值
    handleAppRule(bundleID: bundleID)
}

// MARK: - 窗口规则

/// 检查指定 App 是否配置了窗口规则
func hasWindowRules(for bundleID: String) -> Bool {
    guard let rules = config.windowRules else { return false }
    return rules.contains(where: { $0.bundleID == bundleID })
}

/// 评估窗口规则：从上到下依次匹配，命中后立即切换。
/// 若未命中任何窗口规则，回退到应用级规则。
/// - Parameters:
///   - bundleID: 当前前台应用的 Bundle ID
///   - context: 当前窗口的上下文（Chrome URL 或终端窗口标题）
func evaluateWindowRules(bundleID: String, context: String) {
    guard let windowRules = config.windowRules else {
        handleAppRule(bundleID: bundleID)
        return
    }

    let appRules = windowRules.filter { $0.bundleID == bundleID }
    guard !appRules.isEmpty else {
        handleAppRule(bundleID: bundleID)
        return
    }

    // 依次匹配窗口规则（配置顺序决定优先级）
    for rule in appRules {
        if context.range(of: rule.pattern, options: .regularExpression) != nil {
            if rule.inputSource != currentInputSourceID() {
                print("🏢 窗口规则命中: 「\(rule.pattern)」→ \(rule.inputSource)")
                selectInputSource(id: rule.inputSource)
            } else {
                print("⏭️ 窗口规则命中，但当前已是 \(rule.inputSource)")
            }
            return
        }
    }

    // 无窗口规则匹配 → 回退到应用级规则
    handleAppRule(bundleID: bundleID)
}

// MARK: - 应用级规则

/// 按应用级规则切换输入法：记忆缓存 → 配置规则 → 默认值
func handleAppRule(bundleID: String) {
    // 1. 记忆缓存优先（用户手动选择 > 配置规则）
    if let cachedID = AppKeyboardCache.shared.inputSource(for: bundleID) {
        if cachedID != currentInputSourceID() {
            selectInputSource(id: cachedID)
        }
        return
    }

    // 2. 配置规则兜底
    if let ruleTarget = config.rules[bundleID] {
        if ruleTarget != currentInputSourceID() {
            selectInputSource(id: ruleTarget)
        }
        return
    }

    // 3. 全局默认值
    if let def = config.defaultInputSource {
        if def != currentInputSourceID() {
            selectInputSource(id: def)
        }
    }
}
