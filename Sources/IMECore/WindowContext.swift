import Foundation

// MARK: - 窗口上下文（结构化，替代旧的 "title:... | proc:..." 字符串协议）

/// 当前窗口的上下文信息，由 WindowContextProvider 产出，供窗口规则匹配和菜单使用。
///
/// - 浏览器（Chrome / ego lite）：只有 `url`
/// - Ghostty：`title`（窗口标题）和 `processes`（进程树中的程序名）
public struct WindowContext: Equatable {
    /// 当前标签页 URL（浏览器）
    public var url: String?
    /// 窗口标题（Ghostty）
    public var title: String?
    /// 窗口进程树中的程序名，去重（Ghostty）
    public var processes: [String]

    public init(url: String? = nil, title: String? = nil, processes: [String] = []) {
        self.url = url
        self.title = title
        self.processes = processes
    }

    /// 供窗口规则正则匹配的序列化文本。
    ///
    /// 刻意保持与旧版字符串协议完全一致的格式，
    /// 已有配置里的 pattern（如 `proc:.*\bvim\b.*`）无需修改即可继续命中：
    /// - 浏览器 → 裸 URL
    /// - Ghostty → `title:<标题> | proc:<逗号分隔的程序名>`
    public var matchString: String {
        if let url { return url }
        var parts: [String] = []
        if let title { parts.append("title:\(title)") }
        if !processes.isEmpty { parts.append("proc:\(processes.joined(separator: ","))") }
        return parts.joined(separator: " | ")
    }
}
