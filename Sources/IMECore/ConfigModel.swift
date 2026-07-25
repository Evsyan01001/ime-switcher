import Foundation

// MARK: - 配置结构

/// 应用配置（对应 ~/.config/ime-switcher/config.json）
public struct Config: Codable {
    public var rules: [String: String]
    public var defaultInputSource: String?
    /// 在哪些 App 里触发切换到拼音（写中文注释用）
    public var hashTriggerApps: [String]?
    /// 触发键，默认 `#`
    public var hashTriggerKey: String?
    /// # 触发模式下切到的中文输入法 ID（默认取自动检测到的中文输入法）
    public var hashTriggerChineseSource: String?
    /// # 触发模式下 Enter 后切回的英文输入法 ID（默认取自动检测到的英文布局）
    public var hashTriggerEnglishSource: String?
    /// 窗口级规则（适用于同一 App 内不同窗口/标签页使用不同输入法）
    public var windowRules: [WindowRule]?

    public init(
        rules: [String: String],
        defaultInputSource: String?,
        hashTriggerApps: [String]? = nil,
        hashTriggerKey: String? = nil,
        hashTriggerChineseSource: String? = nil,
        hashTriggerEnglishSource: String? = nil,
        windowRules: [WindowRule]? = nil
    ) {
        self.rules = rules
        self.defaultInputSource = defaultInputSource
        self.hashTriggerApps = hashTriggerApps
        self.hashTriggerKey = hashTriggerKey
        self.hashTriggerChineseSource = hashTriggerChineseSource
        self.hashTriggerEnglishSource = hashTriggerEnglishSource
        self.windowRules = windowRules
    }
}

// MARK: - 窗口规则

/// 按窗口上下文（URL/标题）匹配的输入法规则
///
/// 优先级：窗口规则 > 键盘记忆 > 应用级规则 > 全局默认
public struct WindowRule: Codable, Equatable {
    /// 应用 Bundle ID（如 "com.google.Chrome"、"com.mitchellh.ghostty"）
    public let bundleID: String
    /// 正则表达式，匹配 Chrome 的标签 URL 或终端的窗口标题/进程名
    public let pattern: String
    /// 匹配后切换到的输入法 ID（如 "com.apple.inputmethod.SCIM.ITABC"）
    public let inputSource: String

    public init(bundleID: String, pattern: String, inputSource: String) {
        self.bundleID = bundleID
        self.pattern = pattern
        self.inputSource = inputSource
    }
}
