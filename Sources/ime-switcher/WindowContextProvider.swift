import Foundation

// MARK: - 窗口上下文获取协议

/// 获取当前窗口的上下文信息（用于匹配窗口规则）
protocol WindowContextProvider {
    /// 返回当前窗口的上下文字符串
    /// - Chrome: 当前标签页 URL
    /// - Ghostty: 当前窗口标题
    func currentContext() -> String?
}

// MARK: - Chrome 实现（获取当前标签页 URL）

final class ChromeContextProvider: WindowContextProvider {
    func currentContext() -> String? {
        runOSAScript("tell application \"Google Chrome\" to get URL of active tab of front window")
    }
}

// MARK: - Ghostty 实现（获取当前窗口标题）

final class GhosttyContextProvider: WindowContextProvider {
    func currentContext() -> String? {
        runOSAScript("tell application \"Ghostty\" to get name of front window")
    }
}

// MARK: - AppleScript 执行引擎

/// 通过 /usr/bin/osascript 执行 AppleScript，返回 stdout 输出（去除了结尾换行）
func runOSAScript(_ source: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]

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
                print("⚠️ osascript 错误: \(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result?.isEmpty == true ? nil : result
    } catch {
        print("⚠️ osascript 执行失败: \(error.localizedDescription)")
        return nil
    }
}
