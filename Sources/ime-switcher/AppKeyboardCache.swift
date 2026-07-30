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
///
/// 线程安全：`handleChange()` 在 CFNotificationCenter 的投递线程上执行，
/// 其余 API 在主线程执行，内部用锁保护 `cache` 字典。
final class AppKeyboardCache {
    private let tracker: InputSwitchTracker
    private let inputSourceManager: InputSourceManager

    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private let saveURL: URL

    init(tracker: InputSwitchTracker, inputSourceManager: InputSourceManager) {
        self.tracker = tracker
        self.inputSourceManager = inputSourceManager
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
        lock.lock()
        defer { lock.unlock() }
        return cache[bundleID]
    }

    /// 删除某个 App 的缓存
    func remove(bundleID: String) {
        lock.lock()
        cache.removeValue(forKey: bundleID)
        lock.unlock()
        save()
        print("🧠 已忘记 \(bundleID) 的偏好")
    }

    /// 清除全部记忆缓存
    func removeAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
        save()
        print("🧠 已清除全部输入法记忆")
    }

    /// 缓存是否为空（供菜单栏判断是否展示清除入口）
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache.isEmpty
    }

    /// 当前前台应用是否有缓存
    var hasCacheForFrontmostApp: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        lock.lock()
        defer { lock.unlock() }
        return cache[bundleID] != nil
    }

    // MARK: - 输入法变更处理（CFNotificationCenter 投递线程）

    fileprivate func handleChange() {
        guard let currentID = inputSourceManager.currentInputSourceID(),
              let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else { return }

        // 是我们自己刚触发的切换（规则匹配 / # 触发拼音 / Enter 切回英文等），
        // 不当作用户手动切换记录，避免污染记忆缓存
        if tracker.isOwnSwitch(currentID) { return }

        // 到达这里说明是用户手动切换
        tracker.recordManualChange()

        lock.lock()
        let changed = cache[bundleID] != currentID
        if changed {
            cache[bundleID] = currentID
        }
        lock.unlock()

        if changed {
            save()
            print("🧠 已记住 \(frontApp.localizedName ?? bundleID) → \(inputSourceManager.inputSourceName(forID: currentID) ?? currentID)")
        }
    }

    // MARK: - 持久化

    private func save() {
        lock.lock()
        let snapshot = cache
        lock.unlock()
        do {
            try FileManager.default.createDirectory(
                at: saveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
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
