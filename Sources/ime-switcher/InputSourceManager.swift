import Carbon
import Foundation

// MARK: - 切换事件时间线

/// 程序化/手动切换事件的时间线（线程安全）。
///
/// `InputSourceManager` 记录程序化切换，`AppKeyboardCache` 记录手动切换，
/// 双方通过它区分「自己触发的切换」和「用户手动切换」。
///
/// 用「通知里的新 ID 是否等于最后一次程序化切换的目标 ID」判断是否是我们
/// 自己触发的切换，而不是用一个时刻性的布尔开关 —— 分布式通知的送达时机
/// 不确定，布尔开关在「设 true → 调用 API → 设 false」这几行代码执行完之后、
/// 通知真正送达之前，存在一个会被误判的竞争窗口。
final class InputSwitchTracker {
    private let lock = NSLock()
    private var programmaticTargetID: String?
    private var programmaticSwitchTime: Date?
    private var manualChangeTime: Date?

    /// 记录一次程序化切换（在调用 TISSelectInputSource 之前调用）
    func recordProgrammaticSwitch(targetID: String) {
        lock.lock()
        programmaticTargetID = targetID
        programmaticSwitchTime = Date()
        lock.unlock()
    }

    /// 记录一次用户手动切换
    func recordManualChange() {
        lock.lock()
        manualChangeTime = Date()
        lock.unlock()
    }

    /// 通知送达的新输入法是否等于我们最后一次程序化切换的目标
    func isOwnSwitch(_ currentID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentID == programmaticTargetID
    }

    /// 用户手动切换是否晚于最后一次程序化切换。
    /// 验证重试（selectInputSource 的 130ms 延迟补切）发现该情况时放弃重试，
    /// 避免覆盖用户刚刚的手动选择。
    func manualChangeSupersedesProgrammaticSwitch() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let manual = manualChangeTime, let programmatic = programmaticSwitchTime else { return false }
        return manual > programmatic
    }
}

// MARK: - 输入法查询与切换 (Carbon TIS API)

/// 输入法管理器：封装 TIS 查询与切换。
/// 除 `currentInputSourceID()` 可从任意线程调用外，其余方法均在主线程使用。
final class InputSourceManager {
    let tracker: InputSwitchTracker

    init(tracker: InputSwitchTracker) {
        self.tracker = tracker
    }

    /// 根据输入法 ID 查找 TISInputSource
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

    /// 切换到指定输入法（内置验证重试，确保 CJKV 输入法可靠生效）
    func selectInputSource(id: String) {
        guard let source = findInputSource(withID: id) else {
            print("⚠️ 找不到输入法: \(id)")
            return
        }

        // 记录目标 ID，代替时刻性布尔开关（见 InputSwitchTracker 里的说明）
        tracker.recordProgrammaticSwitch(targetID: id)

        let result = TISSelectInputSource(source)
        if result != noErr {
            print("⚠️ 切换失败,错误码 \(result)")
            return
        }

        print("✅ 已切换到: \(id)")

        // ── 验证重试: CJKV 输入法可能延迟生效 ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self, id] in
            guard let self, self.currentInputSourceID() != id else { return }

            // 用户在这 130ms 内手动切了输入法 → 尊重用户选择，放弃补切
            if self.tracker.manualChangeSupersedesProgrammaticSwitch() {
                print("⏭️ 检测到手动切换，放弃补充切换: \(id)")
                return
            }

            print("⏳ 补充切换: \(id)")
            if let retrySource = self.findInputSource(withID: id) {
                self.tracker.recordProgrammaticSwitch(targetID: id)
                TISSelectInputSource(retrySource)
                if self.currentInputSourceID() == id {
                    print("✅ 补充切换生效: \(id)")
                } else {
                    print("⚠️ 补充切换仍未生效: \(id)")
                }
            }
        }
    }

    /// 获取当前实际选中的输入法 ID
    func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// 获取所有可选的键盘输入法列表 (ID, 名称)。静态方法：不依赖实例状态，
    /// ConfigStore 首次自动创建配置时也可直接使用。
    static func selectableInputSources() -> [(id: String, name: String)] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        var results: [(String, String)] = []
        for source in list {
            guard let catPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else { continue }
            let category = Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String
            guard category == kTISCategoryKeyboardInputSource as String else { continue }

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
}
