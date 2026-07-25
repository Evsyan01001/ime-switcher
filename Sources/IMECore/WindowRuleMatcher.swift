import Foundation

// MARK: - 窗口规则匹配（纯逻辑，无系统依赖，可单元测试）

/// 在窗口规则中为指定 App 匹配上下文，返回命中的规则。
/// 只考虑该 App 的规则，按配置顺序从上到下匹配，命中即止。
/// 非法正则不视为命中（避免配置笔误导致崩溃或误匹配）。
public func matchWindowRule(_ rules: [WindowRule], bundleID: String, context: String) -> WindowRule? {
    for rule in rules where rule.bundleID == bundleID {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
        let range = NSRange(context.startIndex..., in: context)
        if regex.firstMatch(in: context, range: range) != nil {
            return rule
        }
    }
    return nil
}
