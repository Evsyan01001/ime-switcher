import Cocoa
import IMECore

// MARK: - 窗口上下文获取协议

/// 获取当前窗口的上下文信息（用于匹配窗口规则）
protocol WindowContextProvider {
    /// 返回当前窗口的结构化上下文
    /// - Chrome / ego lite: 当前标签页 URL
    /// - Ghostty: 窗口标题 + 进程中运行的程序
    func currentContext() -> WindowContext?
}

// MARK: - Chrome 实现（获取当前标签页 URL）

final class ChromeContextProvider: WindowContextProvider {
    func currentContext() -> WindowContext? {
        runOSAScript("tell application \"Google Chrome\" to get URL of active tab of front window")
            .map { WindowContext(url: $0) }
    }
}

// MARK: - ego lite 实现（Chromium 内核，AppleScript 接口与 Chrome 相同）

final class EgoLiteContextProvider: WindowContextProvider {
    func currentContext() -> WindowContext? {
        runOSAScript("tell application \"ego lite\" to get URL of active tab of front window")
            .map { WindowContext(url: $0) }
    }
}

// MARK: - Ghostty 实现（窗口标题 + 进程检测）

/// 通过 Accessibility API 获取窗口标题，并通过进程树遍历检测当前运行的程序。
/// 窗口规则可以同时匹配标题和运行中的程序（见 WindowContext.matchString）。
final class GhosttyContextProvider: WindowContextProvider {
    func currentContext() -> WindowContext? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.mitchellh.ghostty" && $0.isActive
        }) else { return nil }

        let ghosttyPID = app.processIdentifier

        // 1) 获取 AX 窗口标题
        let title = axWindowTitle(pid: ghosttyPID)

        // 2) 获取进程树中的子进程名
        let procs = descendantProcessNames(parentPID: ghosttyPID)

        guard title != nil || !procs.isEmpty else { return nil }

        return WindowContext(title: title, processes: procs)
    }

    /// 通过 AX API 读取当前焦点窗口标题
    private func axWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXFocusedWindow" as CFString, &focusedWindow) == .success,
              let window = focusedWindow,
              // 防御性校验：异常状态下返回的可能不是 AXUIElement，直接 as! 会崩溃
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let axWindow = window as! AXUIElement // 上面已校验类型，此处安全

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, "AXTitle" as CFString, &title) == .success,
              let t = title as? String, !t.isEmpty else { return nil }
        return t
    }

    /// 通过 sysctl 读取内核进程表，遍历进程树返回所有子进程的程序名（去重）。
    /// 相比每 500ms fork 一次 `ps`，直接读内核开销小得多。
    private func descendantProcessNames(parentPID: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }

        // 建立 PPID → [(PID, name)] 映射
        var children: [pid_t: [(pid_t, String)]] = [:]
        for kp in procs.prefix(size / MemoryLayout<kinfo_proc>.stride) {
            var comm = kp.kp_proc.p_comm
            let commCapacity = MemoryLayout.size(ofValue: comm)
            let name = withUnsafePointer(to: &comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: commCapacity) {
                    String(cString: $0)
                }
            }
            children[kp.kp_eproc.e_ppid, default: []].append((kp.kp_proc.p_pid, name))
        }

        var seen = Set<String>()
        var result: [String] = []

        func walk(pid: pid_t) {
            for (childPid, name) in children[pid] ?? [] {
                if seen.insert(name).inserted {
                    result.append(name)
                }
                // 递归遍历子进程的子进程（如 zsh → claude）
                walk(pid: childPid)
            }
        }

        walk(pid: parentPID)
        return result
    }
}

// MARK: - 进程执行引擎

/// 通过 /usr/bin/osascript 执行 AppleScript
func runOSAScript(_ source: String) -> String? {
    runCommand(executable: "/usr/bin/osascript", arguments: ["-e", source])
}

/// 自动化权限（-1743）警告是否已打印过。
/// 被拒绝后每次 osascript 都会失败，窗口监控 500ms 轮询会把日志刷爆，
/// 因此同一进程生命周期内只提示一次；授权后调用自然恢复成功，无需重置。
private var automationDeniedWarned = false

/// 通用进程执行：启动可执行文件，捕获 stdout，返回输出文本
private func runCommand(executable: String, arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    let errorPipe = Pipe()
    process.standardError = errorPipe

    do {
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errMsg = String(data: errData, encoding: .utf8), !errMsg.isEmpty {
                let trimmed = errMsg.trimmingCharacters(in: .whitespacesAndNewlines)

                // -1743 = errAEEventNotPermitted：用户在「想要控制 xxx」弹窗点了拒绝，
                // 或自动化权限被关闭。给出可操作的指引，而不是混在通用错误里。
                if trimmed.contains("-1743") || trimmed.contains("Not authorized to send Apple events") {
                    if !automationDeniedWarned {
                        automationDeniedWarned = true
                        print("⚠️ 自动化权限被拒绝：无法通过 AppleScript 控制其他 App（窗口规则暂不生效）")
                        print("   → 系统设置 → 隐私与安全性 → 自动化 → 允许 ime-switcher 控制对应应用")
                        print("   → 然后重启程序: launchctl kickstart -k gui/\(getuid())/com.user.ime-switcher")
                    }
                    return nil
                }

                print("⚠️ 命令执行错误: \(trimmed)")
            }
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result?.isEmpty == true ? nil : result
    } catch {
        print("⚠️ 命令执行失败: \(error.localizedDescription)")
        return nil
    }
}
