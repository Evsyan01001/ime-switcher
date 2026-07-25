import Cocoa
import Carbon

// MARK: - 手动切换检测回调（C 函数指针，供 CFNotificationCenter 使用）

private func _onInputSourceChanged(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    Unmanaged<AppKeyboardCache>.fromOpaque(observer).takeUnretainedValue().handleChange()
}

/// 记住每个 App 上次手动使用的输入法，下次切回时自动恢复。
///
/// 优先级：记忆缓存 > 配置规则 > 默认值。
/// 用户在某个 App 里手动切换输入法后自动记录，覆盖固定规则。
final class AppKeyboardCache {
    static let shared = AppKeyboardCache()

    /// 记录我们自己最后一次程序化切换的目标输入法 ID。
    /// 用「通知里的新 ID 是否等于这个值」判断是否是我们自己触发的切换，
    /// 而不是用一个时刻性的布尔开关 —— 分布式通知的送达时机不确定，
    /// 布尔开关在「设 true → 调用 API → 设 false」这几行代码执行完之后、
    /// 通知真正送达之前，存在一个会被误判的竞争窗口。
    static var lastProgrammaticTargetID: String?

    /// 最后一次程序化切换的发起时间（配合 lastManualChangeTime 判断重试是否应放弃）
    static var lastProgrammaticSwitchTime: Date?

    /// 最后一次检测到用户手动切换输入法的时间。
    /// 验证重试（selectInputSource 的 130ms 延迟补切）发现该时间晚于
    /// 程序化切换时间时放弃重试，避免覆盖用户刚刚的手动选择。
    static var lastManualChangeTime: Date?

    private var cache: [String: String] = [:]
    private let saveURL: URL

    private init() {
        let home = NSHomeDirectory()
        let path = (home as NSString).appendingPathComponent(".config/ime-switcher/app-keyboard-cache.json")
        saveURL = URL(fileURLWithPath: path)
        load()
        pruneStaleEntries()
        registerInputSourceObserver()
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            unsafeBitCast(kTISNotifySelectedKeyboardInputSourceChanged, to: CFNotificationName?.self),
            nil
        )
    }

    // MARK: - Public API

    /// 获取某个 App 缓存的输入法
    func inputSource(for bundleID: String) -> String? {
        cache[bundleID]
    }

    /// 删除某个 App 的缓存
    func remove(bundleID: String) {
        cache.removeValue(forKey: bundleID)
        save()
        print("🧠 已忘记 \(bundleID) 的偏好")
    }

    /// 清除全部记忆缓存
    func removeAll() {
        cache.removeAll()
        save()
        print("🧠 已清除全部输入法记忆")
    }

    /// 缓存是否为空（供菜单栏判断是否展示清除入口）
    var isEmpty: Bool {
        cache.isEmpty
    }

    /// 当前前台应用是否有缓存
    var hasCacheForFrontmostApp: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return cache[bundleID] != nil
    }

    // MARK: - 输入法变更处理

    fileprivate func handleChange() {
        guard let currentID = currentInputSourceID(),
              let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else { return }

        // 是我们自己刚触发的切换（规则匹配 / # 触发拼音 / Enter 切回英文等），
        // 不当作用户手动切换记录，避免污染记忆缓存
        if currentID == Self.lastProgrammaticTargetID { return }

        // 到达这里说明是用户手动切换
        Self.lastManualChangeTime = Date()

        if cache[bundleID] != currentID {
            cache[bundleID] = currentID
            save()
            print("🧠 已记住 \(frontApp.localizedName ?? bundleID) → \(inputSourceName(forID: currentID) ?? currentID)")
        }
    }

    // MARK: - 持久化

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: saveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: saveURL)
        } catch {
            print("⚠️ 记忆缓存保存失败: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        cache = decoded
        print("🧠 已加载 \(cache.count) 条输入法记忆")
    }

    /// 清理已卸载 App 的记忆条目（启动时调用一次，防止缓存无限增长）
    private func pruneStaleEntries() {
        let stale = cache.keys.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) == nil
        }
        guard !stale.isEmpty else { return }
        stale.forEach { cache.removeValue(forKey: $0) }
        save()
        print("🧠 已清理 \(stale.count) 条失效记忆（App 已卸载）")
    }

    // MARK: - 监听系统输入法变化通知

    private func registerInputSourceObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            _onInputSourceChanged,
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }
}
