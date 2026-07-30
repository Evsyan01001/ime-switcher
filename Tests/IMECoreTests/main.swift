import Foundation
import IMECore

// 轻量测试运行器（无 XCTest 依赖，仅需 Command Line Tools）
// 运行方式: swift run IMECoreTests   （全部通过退出码 0，否则 1）

private var failures = 0
private var passes = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        passes += 1
        print("  ✅ \(name)")
    } else {
        failures += 1
        print("  ❌ \(name)")
    }
}

func checkEqual<T: Equatable>(_ actual: T?, _ expected: T?, _ name: String) {
    check(actual == expected, "\(name)（期望 \(String(describing: expected))，实际 \(String(describing: actual))")
}

// MARK: - 窗口规则匹配

let rules = [
    WindowRule(bundleID: "com.google.Chrome", pattern: "zhihu|baidu", inputSource: "com.apple.inputmethod.SCIM.ITABC"),
    WindowRule(bundleID: "com.google.Chrome", pattern: "github|stackoverflow", inputSource: "com.apple.keylayout.ABC"),
    WindowRule(bundleID: "com.mitchellh.ghostty", pattern: "vim|nvim", inputSource: "com.apple.inputmethod.SCIM.ITABC"),
]

print("窗口规则匹配:")

let hitZhihu = matchWindowRule(rules, bundleID: "com.google.Chrome", context: "https://zhihu.com/question/123")
checkEqual(hitZhihu?.inputSource, "com.apple.inputmethod.SCIM.ITABC", "按 Bundle ID + 正则命中")

// 上下文同时命中多条规则时，配置在前的胜出
let hitBoth = matchWindowRule(rules, bundleID: "com.google.Chrome", context: "zhihu github")
checkEqual(hitBoth?.pattern, "zhihu|baidu", "多条命中时配置顺序优先")

let hitSafari = matchWindowRule(rules, bundleID: "com.apple.Safari", context: "https://zhihu.com")
check(hitSafari == nil, "其他 App 的规则被忽略")

check(matchWindowRule(rules, bundleID: "com.google.Chrome", context: "https://apple.com") == nil,
      "无匹配返回 nil")

let hitGhostty = matchWindowRule(rules, bundleID: "com.mitchellh.ghostty", context: "title:~ | proc:zsh,vim")
checkEqual(hitGhostty?.inputSource, "com.apple.inputmethod.SCIM.ITABC", "Ghostty 上下文可匹配进程名")

let badRule = [WindowRule(bundleID: "a", pattern: "[", inputSource: "x")]
check(matchWindowRule(badRule, bundleID: "a", context: "anything") == nil,
      "非法正则按不匹配处理（不崩溃）")

check(matchWindowRule([], bundleID: "com.google.Chrome", context: "https://zhihu.com") == nil,
      "空规则数组返回 nil")

// MARK: - 配置模型编解码

print("配置模型编解码:")

do {
    let json = #"{"rules":{"com.apple.Terminal":"com.apple.keylayout.ABC"}}"#
    let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    checkEqual(config.rules["com.apple.Terminal"], "com.apple.keylayout.ABC", "最小配置可解码")
    check(config.windowRules == nil && config.hashTriggerKey == nil && config.defaultInputSource == nil,
          "缺省可选字段解码为 nil")
} catch {
    check(false, "最小配置可解码（抛出 \(error)）")
}

do {
    let json = """
    {
      "rules": {"com.apple.Terminal": "com.apple.keylayout.ABC"},
      "defaultInputSource": "com.apple.keylayout.ABC",
      "hashTriggerKey": "#",
      "hashTriggerApps": ["com.apple.Terminal"],
      "windowRules": [
        {"bundleID": "com.google.Chrome", "pattern": "zhihu", "inputSource": "com.apple.inputmethod.SCIM.ITABC"}
      ]
    }
    """
    let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    checkEqual(config.windowRules?.count, 1, "完整配置 windowRules 解码")
    checkEqual(config.hashTriggerApps, ["com.apple.Terminal"], "完整配置 hashTriggerApps 解码")
} catch {
    check(false, "完整配置可解码（抛出 \(error)）")
}

do {
    let original = Config(
        rules: ["a": "b"],
        defaultInputSource: "com.apple.keylayout.ABC",
        hashTriggerApps: ["x"],
        hashTriggerKey: "#",
        windowRules: [WindowRule(bundleID: "b", pattern: "p", inputSource: "i")]
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Config.self, from: data)
    check(decoded.rules == original.rules
          && decoded.defaultInputSource == original.defaultInputSource
          && decoded.windowRules == original.windowRules,
          "编码→解码往返一致")
} catch {
    check(false, "编码→解码往返一致（抛出 \(error)）")
}

check((try? JSONDecoder().decode(Config.self, from: Data("{".utf8))) == nil,
      "非法 JSON 解码抛错（loadConfig 据此提示用户）")

// MARK: - WindowContext 结构化上下文

print("WindowContext 结构化上下文:")

checkEqual(WindowContext(url: "https://zhihu.com/question/123").matchString,
           "https://zhihu.com/question/123", "浏览器上下文序列化为裸 URL")

checkEqual(WindowContext(title: "~", processes: ["zsh", "vim"]).matchString,
           "title:~ | proc:zsh,vim", "Ghostty 上下文序列化保持旧格式（向后兼容）")

checkEqual(WindowContext(title: "vim README.md").matchString,
           "title:vim README.md", "仅标题时无 proc 段")

checkEqual(WindowContext(processes: ["zsh", "claude"]).matchString,
           "proc:zsh,claude", "仅进程时无 title 段")

checkEqual(WindowContext().matchString, "", "空上下文序列化为空串")

// 旧配置里的 pattern 对结构化上下文依然命中
let ghosttyHit = matchWindowRule(rules, bundleID: "com.mitchellh.ghostty",
                                 context: WindowContext(title: "~", processes: ["zsh", "vim"]).matchString)
checkEqual(ghosttyHit?.inputSource, "com.apple.inputmethod.SCIM.ITABC",
           "结构化上下文可被旧 pattern 命中")

// MARK: - 输入法决策（resolveInputSource）

print("输入法决策:")

let resolverConfig = Config(
    rules: ["com.microsoft.VSCode": "com.apple.keylayout.ABC"],
    defaultInputSource: "com.apple.keylayout.US",
    windowRules: [WindowRule(bundleID: "com.google.Chrome", pattern: "zhihu", inputSource: "com.apple.inputmethod.SCIM.ITABC")]
)

// 窗口规则 > 记忆缓存
let d1 = resolveInputSource(config: resolverConfig, bundleID: "com.google.Chrome",
                            cachedID: "com.apple.keylayout.ABC",
                            context: WindowContext(url: "https://zhihu.com"))
checkEqual(d1, InputSourceDecision(targetID: "com.apple.inputmethod.SCIM.ITABC",
                                   reason: .windowRule(pattern: "zhihu")),
           "窗口规则优先于记忆缓存")

// context 为 nil 时不评估窗口规则 → 落到记忆缓存
let d2 = resolveInputSource(config: resolverConfig, bundleID: "com.google.Chrome",
                            cachedID: "com.apple.keylayout.ABC", context: nil)
checkEqual(d2, InputSourceDecision(targetID: "com.apple.keylayout.ABC", reason: .remembered),
           "无上下文时记忆缓存优先")

// 窗口规则未命中 → 记忆缓存
let d3 = resolveInputSource(config: resolverConfig, bundleID: "com.google.Chrome",
                            cachedID: "com.apple.keylayout.ABC",
                            context: WindowContext(url: "https://apple.com"))
checkEqual(d3?.reason, .remembered, "窗口规则未命中回退到记忆缓存")

// 无记忆 → 应用级规则
let d4 = resolveInputSource(config: resolverConfig, bundleID: "com.microsoft.VSCode",
                            cachedID: nil, context: nil)
checkEqual(d4, InputSourceDecision(targetID: "com.apple.keylayout.ABC", reason: .appRule),
           "应用级规则命中")

// 无记忆无应用规则 → 全局默认
let d5 = resolveInputSource(config: resolverConfig, bundleID: "com.example.Other",
                            cachedID: nil, context: nil)
checkEqual(d5, InputSourceDecision(targetID: "com.apple.keylayout.US", reason: .fallback),
           "全局默认兜底")

// 全部未命中 → nil（不切换）
let noDefault = Config(rules: [:], defaultInputSource: nil)
check(resolveInputSource(config: noDefault, bundleID: "com.example.Other",
                         cachedID: nil, context: nil) == nil,
      "全部未命中返回 nil")

check(appHasWindowRules(resolverConfig, bundleID: "com.google.Chrome"), "appHasWindowRules 命中")
check(!appHasWindowRules(resolverConfig, bundleID: "com.microsoft.VSCode"), "appHasWindowRules 未命中")

// MARK: - 结果

print("\n通过 \(passes) 项，失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
