import Cocoa

// MARK: - 应用切换逻辑

func handleAppActivation(_ app: NSRunningApplication) {
    guard let bundleID = app.bundleIdentifier else { return }

    // 1. 记忆缓存优先（用户手动选择 > 配置规则）
    if let cachedID = AppKeyboardCache.shared.inputSource(for: bundleID) {
        if cachedID != currentInputSourceID() {
            selectInputSource(id: cachedID)
        }
        return
    }

    // 2. 配置规则兜底
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
