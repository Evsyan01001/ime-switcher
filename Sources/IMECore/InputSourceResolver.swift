import Foundation

// MARK: - 输入法决策（纯逻辑，无系统依赖，可单元测试）

/// 决策来源（用于日志与测试断言）
public enum InputSourceDecisionReason: Equatable {
    /// 窗口规则命中（携带命中的 pattern）
    case windowRule(pattern: String)
    /// 手动切换记忆
    case remembered
    /// 应用级 rules
    case appRule
    /// 全局默认
    case fallback
}

/// 输入法决策结果
public struct InputSourceDecision: Equatable {
    public let targetID: String
    public let reason: InputSourceDecisionReason

    public init(targetID: String, reason: InputSourceDecisionReason) {
        self.targetID = targetID
        self.reason = reason
    }
}

/// 指定 App 是否配置了窗口规则
public func appHasWindowRules(_ config: Config, bundleID: String) -> Bool {
    config.windowRules?.contains(where: { $0.bundleID == bundleID }) ?? false
}

/// 按优先级决定目标输入法：窗口规则 > 记忆缓存 > 应用级规则 > 全局默认。
///
/// - Parameters:
///   - config: 当前配置
///   - bundleID: 前台应用 Bundle ID
///   - cachedID: 该 App 的手动切换记忆（无则传 nil）
///   - context: 当前窗口上下文。传 nil 表示不评估窗口规则
///     （配置了窗口规则的 App 在激活时不评估，等 WindowMonitor 回调时再评估）
/// - Returns: 决策结果；任何一级都未命中时返回 nil（不切换）
public func resolveInputSource(
    config: Config,
    bundleID: String,
    cachedID: String?,
    context: WindowContext?
) -> InputSourceDecision? {
    if let context, let rules = config.windowRules,
       let rule = matchWindowRule(rules, bundleID: bundleID, context: context.matchString) {
        return InputSourceDecision(targetID: rule.inputSource, reason: .windowRule(pattern: rule.pattern))
    }
    if let cachedID {
        return InputSourceDecision(targetID: cachedID, reason: .remembered)
    }
    if let target = config.rules[bundleID] {
        return InputSourceDecision(targetID: target, reason: .appRule)
    }
    if let target = config.defaultInputSource {
        return InputSourceDecision(targetID: target, reason: .fallback)
    }
    return nil
}
