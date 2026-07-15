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

    /// 标记当前正在程序化切换，用于挡掉我们自己的切换通知
    static var isProgrammaticSwitch = false

    private var cache: [String: String] = [:]
    private let saveURL: URL

    private init() {
        let home = NSHomeDirectory()
        let path = (home as NSString).appendingPathComponent(".config/ime-switcher/app-keyboard-cache.json")
        saveURL = URL(fileURLWithPath: path)
        load()
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

    /// 当前前台应用是否有缓存
    var hasCacheForFrontmostApp: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return cache[bundleID] != nil
    }

    // MARK: - 输入法变更处理

    fileprivate func handleChange() {
        guard !Self.isProgrammaticSwitch else { return }
        guard let currentID = currentInputSourceID(),
              let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else { return }

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
