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

// MARK: - 结果

print("\n通过 \(passes) 项，失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
