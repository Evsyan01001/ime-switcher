import Cocoa
import Carbon

// MARK: - # 触发拼音（注释模式）

/// 在配置的 App 中按 `#` 时自动切换到拼音（写中文注释），
/// 按 Enter 后自动切回英文。通过 `hashTriggerApps` 配置生效范围。
final class HashTrigger {
    private var eventTap: CFMachPort?
    private var isInCommentMode = false
    private var appSwitchObserver: NSObjectProtocol?

    // kVK_Return = 36, kVK_ANSI_KeypadEnter = 76
    private let returnKeyCodes: Set<Int64> = [36, 76]

    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<HashTrigger>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { service.handle(event: event) }
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            print("⚠️ #触发拼音 需要权限（以下任选其一）")
            print("   1. 系统设置 > 隐私与安全性 > 辅助功能")
            print("      → 点击 + 添加 `/Volumes/T7/coding/inputSource/ime-switcher`")
            print("   2. 或 隐私与安全性 > 输入监控（同上）")
            print("   添加后完全退出本程序（kill），再重新启动")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // 切到别的 App 时清空注释模式，防止状态串到其他 App
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInCommentMode = false
        }

        print("🔣 #触发拼音已就绪（\(config.hashTriggerApps?.count ?? 0) 个 App）")
    }

    func stop() {
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFMachPortInvalidate(eventTap)
        self.eventTap = nil
    }

    // MARK: - 事件处理

    private func handle(event: CGEvent) {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }

        // 只在配置的 App 里生效
        guard (config.hashTriggerApps ?? []).contains(bundleID) else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // 按 Enter → 从注释模式回到英文
        if returnKeyCodes.contains(keyCode) {
            if isInCommentMode {
                isInCommentMode = false
                print("🔤 注释结束，切回英文")
                selectInputSource(id: "com.apple.keylayout.ABC")
            }
            return
        }

        // 用实际字符判断 `#`（兼容各键盘布局）
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.characters == "#",
              !isInCommentMode else { return }

        isInCommentMode = true
        print("💬 # 触发注释模式 → 拼音")
        selectInputSource(id: "com.apple.inputmethod.SCIM.ITABC")
    }

}
