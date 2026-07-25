import Cocoa

// MARK: - 窗口上下文获取协议

/// 获取当前窗口的上下文信息（用于匹配窗口规则）
protocol WindowContextProvider {
    /// 返回当前窗口的上下文字符串
    /// - Chrome: 当前标签页 URL
    /// - Ghostty: 窗口标题 + 进程中运行的程序
    func currentContext() -> String?
}

// MARK: - Chrome 实现（获取当前标签页 URL）

final class ChromeContextProvider: WindowContextProvider {
    func currentContext() -> String? {
        runOSAScript("tell application \"Google Chrome\" to get URL of active tab of front window")
    }
}

// MARK: - Ghostty 实现（窗口标题 + 进程检测）

/// 通过 Accessibility API 获取窗口标题，并通过进程树遍历检测当前运行的程序。
///
/// 返回格式: `title:阅读template | proc:zsh,claude`
/// - `title:` 部分 = Ghostty 当前标签页标题
/// - `proc:` 部分 = Ghostty 进程树下的所有子进程名（去重）
///
/// 这样窗口规则可以同时匹配标题和运行中的程序。
final class GhosttyContextProvider: WindowContextProvider {
    func currentContext() -> String? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.mitchellh.ghostty" && $0.isActive
        }) else { return nil }

        let ghosttyPID = app.processIdentifier

        // 1) 获取 AX 窗口标题
        let title = axWindowTitle(pid: ghosttyPID)

        // 2) 获取进程树中的子进程名
        let procs = descendantProcessNames(parentPID: ghosttyPID)

        guard title != nil || !procs.isEmpty else { return nil }

        var parts: [String] = []
        if let t = title {
            parts.append("title:\(t)")
        }
        if !procs.isEmpty {
            parts.append("proc:\(procs.joined(separator: ","))")
        }
        return parts.joined(separator: " | ")
    }

    /// 通过 AX API 读取当前焦点窗口标题
    private func axWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXFocusedWindow" as CFString, &focusedWindow) == .success,
              let window = focusedWindow else { return nil }

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, "AXTitle" as CFString, &title) == .success,
              let t = title as? String, !t.isEmpty else { return nil }
        return t
    }

    /// 通过 ps 遍历进程树，返回所有子进程的程序名（去重）
    private func descendantProcessNames(parentPID: pid_t) -> [String] {
        // 获取全部进程的 PID, PPID, 可执行文件名
        guard let output = runShellCommand("ps -eo pid=,ppid=,comm= 2>/dev/null") else { return [] }

        // 建立 PPID → [(PID, name)] 映射
        var children: [pid_t: [(pid_t, String)]] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }
            let pid = Int32(String(parts[0])) ?? 0
            let ppid = Int32(String(parts[1])) ?? 0
            let comm = String(parts.dropFirst(2).joined(separator: " "))
            children[ppid, default: []].append((pid, comm))
        }

        var seen = Set<String>()
        var result: [String] = []

        func walk(pid: pid_t) {
            for (childPid, comm) in children[pid] ?? [] {
                let name = URL(fileURLWithPath: comm).lastPathComponent
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

/// 执行任意 shell 命令（通过 /bin/bash -c）
func runShellCommand(_ command: String) -> String? {
    runCommand(executable: "/bin/bash", arguments: ["-c", command])
}

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
                print("⚠️ 命令执行错误: \(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))")
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
