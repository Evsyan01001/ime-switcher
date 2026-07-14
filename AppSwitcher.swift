import Cocoa

// MARK: - 应用切换逻辑

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
