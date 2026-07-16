<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.3-F05138?logo=swift" alt="Swift 6.3">
  <img src="https://img.shields.io/badge/macOS-14%2B-0078D4?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License MIT">
  <img src="https://img.shields.io/badge/build-passing-brightgreen" alt="Build">
</p>

<h1 align="center">⌨ ime-switcher</h1>

<p align="center">
  <b>macOS 输入法自动切换工具</b><br>
  根据前台应用自动切换中英文输入法，支持菜单栏一键设置、输入法记忆、<code>#</code> 触发中文注释。
</p>

---

## ✨ 功能一览

| 功能 | 说明 |
|------|------|
| 🔄 **自动切换** | 切换应用时根据规则自动切换输入法 |
| 🧠 **输入法记忆** | 手动切一次输入法，下次自动恢复你的选择 |
| 🎯 **默认兜底** | 未配置规则的应用可指定默认输入法 |
| 🖱️ **菜单栏设置** | 点击 ⌨ 图标，一键为当前应用指定输入法 |
| ✅ **CJKV 可靠切换** | 验证重试机制，确保中日韩越输入法切换不丢 |
| 💬 **注释模式** | 在配置的 App 中按指定键（默认 `#`）自动切拼音写注释 |
| ⌨️ **可自定义触发键** | 注释模式触发键可自由改为任意字符 |

---

## 🚀 快速开始（完整流程）

### 第一步：编译

```bash
# 需要 Xcode Command Line Tools
xcode-select --install

# 克隆
git clone https://github.com/Evsyan01001/ime-switcher.git
cd ime-switcher

# 编译（Swift Package Manager）
./build.sh
# 等价于: swift build -c release
```

编译产物在 `.build/release/` 下。也可直接 `swift build -c release` 效果一样。

### 第二步：首次运行（自动配置）

```bash
# 启动（菜单栏出现 ⌨ 图标）
.build/release/ime-switcher
```

**首次运行时，程序会自动完成以下配置：**

```
📝 首次使用，正在自动配置...
📋 检测到输入法: 英文 → ABC，中文 → 拼音
📄 已生成默认配置（7 条规则）
💡 如需调整：点击菜单栏 ⌨ 图标 → 编辑配置文件
💾 配置已保存: /Users/xxx/.config/ime-switcher/config.json
🚀 ime-switcher v1.2 已启动,正在监听应用切换...
```

✅ 自动检测你系统中的英文和中文输入法  
✅ 自动创建 `~/.config/ime-switcher/config.json`，包含常用 App 的规则  
✅ 自动打开 Terminal、VSCode、iTerm2 的注释模式

> **无需手动创建目录或复制配置文件**，运行即用。

### 第三步：编辑配置（按需）

程序已为你生成默认配置，但你可以随时修改：

```bash
# 查看当前配置
cat ~/.config/ime-switcher/config.json

# 编辑配置
vim ~/.config/ime-switcher/config.json
```

自动生成的默认配置类似：

```json
{
  "rules": {
    "com.apple.Terminal":          "com.apple.keylayout.ABC",
    "com.apple.dt.Xcode":          "com.apple.keylayout.ABC",
    "com.googlecode.iterm2":       "com.apple.keylayout.ABC",
    "com.microsoft.VSCode":        "com.apple.keylayout.ABC",
    "com.apple.Notes":             "com.apple.inputmethod.SCIM.ITABC",
    "com.apple.mobilemail":        "com.apple.inputmethod.SCIM.ITABC",
    "com.tencent.xinWeChat":       "com.apple.inputmethod.SCIM.ITABC"
  },
  "defaultInputSource": null,
  "hashTriggerKey": "#",
  "hashTriggerApps": [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "com.microsoft.VSCode"
  ]
}
```

> **查 Bundle ID：**
> ```bash
> osascript -e 'id of app "微信"'
> mdls -name kMDItemCFBundleIdentifier /Applications/xxx.app
> ```

#### 配置字段说明

| 字段 | 说明 |
|------|------|
| `rules` | Bundle ID → 输入法 ID 映射。切换到该应用时自动使用对应的输入法 |
| `defaultInputSource` | `rules` 里没配置的应用使用此输入法。`null` 表示不切换 |
| `hashTriggerKey` | 注释模式的触发键，默认 `#`。可改为 `\``、`;` 等任意字符 |
| `hashTriggerApps` | 在此列表的 App 中按触发键可自动切到中文输入法写注释 |
| `hashTriggerChineseSource` | 注释模式切换到中文输入法 ID。不填则用自动检测到的第一个中文输入法 |
| `hashTriggerEnglishSource` | 注释模式结束后切回的英文输入法 ID。不填则默认 `ABC` |

### 第四步：通过菜单栏调整规则

启动后点击菜单栏 ⌨ 图标：

1. **「将「当前应用」设为」→ 选输入法**   
   为当前前台应用绑定一个输入法，下次切到它时自动切换
2. **💬 注释模式 → 开关 / 自定义触发键**   
   开启后可在该应用中按 `#`（或你自定义的键）写中文注释
3. **忘记这个 App 的偏好**   
   清除输入法记忆，恢复配置文件中的规则
4. **重新加载配置 / 编辑配置文件**   
   修改配置文件后无需重启程序

---

## 📖 使用场景详解

### 场景一：自动切换（基础功能）

配置好 `rules` 后，在 App 之间切换即可自动切换输入法：

| 正在用的 App | 自动切换到 |
|-------------|-----------|
| Terminal / iTerm2 | 英文 (ABC) |
| VSCode | 英文 (ABC) |
| Xcode | 英文 (ABC) |
| 微信 | 中文拼音 |

### 场景二：输入法记忆（手动覆盖规则）

如果在一个 App 里手动切换了输入法，程序会自动记住你的选择：

- **记忆优先**：手动切换过的 App，记忆优先级高于 `rules` 配置
- **自动恢复**：下次切回该 App 时，恢复你上次手动选的那个输入法
- **清除记忆**：菜单栏 → 「忘记这个 App 的偏好」，恢复配置文件规则

### 场景三：注释模式（写中文注释）

在配置了 `hashTriggerApps` 的 App（如 VSCode、Terminal）中：

1. 按 <kbd>#</kbd>（或你自定义的触发键）  
   → 自动切换到拼音输入法  
   → 左下角提示 `💬 # 触发注释模式 → 拼音`
2. 写中文注释
3. 按 <kbd>Enter</kbd>  
   → 自动切回英文  
   → 左下角提示 `🔤 注释结束，切回英文`

> **需要额外权限：** 首次使用注释模式需要授权。见下方「权限说明」。

### 场景四：菜单栏操作（无需编辑配置文件）

不想手写 JSON？直接通过菜单栏操作：

1. 切换到目标应用
2. 点击菜单栏 ⌨ 图标
3. 「将「当前应用」设为」→ 选择输入法
4. 程序自动将规则写入配置文件

---

## ⚙️ 配置文件参考

### 完整示例

```json
{
  "rules": {
    "com.apple.Terminal":              "com.apple.keylayout.ABC",
    "com.googlecode.iterm2":           "com.apple.keylayout.ABC",
    "com.microsoft.VSCode":            "com.apple.keylayout.ABC",
    "com.apple.dt.Xcode":              "com.apple.keylayout.ABC",
    "com.jetbrains.intellij":          "com.apple.keylayout.ABC",
    "com.tencent.xinWeChat":           "com.apple.inputmethod.SCIM.ITABC",
    "com.apple.mobilemail":            "com.apple.inputmethod.SCIM.ITABC",
    "com.apple.Notes":                 "com.apple.inputmethod.SCIM.ITABC",
    "com.apple.Safari":                "com.apple.inputmethod.SCIM.ITABC",
    "com.microsoft.Excel":             "com.apple.inputmethod.SCIM.ITABC"
  },
  "defaultInputSource": "com.apple.keylayout.ABC",
  "hashTriggerKey": "#",
  "hashTriggerApps": [
    "com.microsoft.VSCode",
    "com.apple.Terminal",
    "com.googlecode.iterm2"
  ]
}
```

### 常用输入法 ID 参考

| 输入法 | ID |
|--------|----|
| 英文 (ABC) | `com.apple.keylayout.ABC` |
| 拼音（简体） | `com.apple.inputmethod.SCIM.ITABC` |
| 五笔 | `com.apple.inputmethod.SCIM.WBX` |
| 双拼 | `com.apple.inputmethod.SCIM.Shuangpin` |
| 美式英文 | `com.apple.keylayout.US` |

> 不确定你的输入法 ID？运行 `.build/release/list-input-sources` 查看。

---

## 🔒 权限说明

| 功能 | 是否需要权限 |
|------|------------|
| 自动切换输入法 | ❌ 不需要 |
| 菜单栏图标与交互 | ❌ 不需要 |
| 输入法记忆 | ❌ 不需要 |
| **注释模式（`#` 触发拼音）** | ✅ 需要辅助功能或输入监控权限 |

**授权步骤：**

1. 打开 **系统设置 → 隐私与安全性**
2. 点击 **辅助功能**（或 **输入监控**）
3. 点击 `+` 添加 `.build/release/ime-switcher`
4. 完全退出程序（`kill`），重新启动

> 如果用 `./build.sh` 重新编译后，二进制路径不变（仍在 `.build/release/`），授权继续有效。

---

## 🔄 开机自启（可选）

```bash
# 1. 将程序复制到系统路径
sudo cp .build/release/ime-switcher /usr/local/bin/ime-switcher

# 2. 安装 LaunchAgent
cp Resources/com.user.ime-switcher.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.ime-switcher.plist
```

**停止 / 卸载：**

```bash
launchctl bootout gui/$(id -u)/com.user.ime-switcher
rm ~/Library/LaunchAgents/com.user.ime-switcher.plist
```

> 开机自启配置了 `KeepAlive`，异常退出后自动重启。日志在 `/tmp/ime-switcher.log` 和 `/tmp/ime-switcher.err`。

---

## 🗂️ 项目结构

```
ime-switcher/
├── Package.swift              # Swift Package Manager 清单
├── Sources/ime-switcher/      # 主程序源码
│   ├── main.swift
│   ├── AppKeyboardCache.swift
│   ├── AppSwitcher.swift
│   ├── Config.swift
│   ├── HashTrigger.swift
│   ├── InputSourceManager.swift
│   └── MenuController.swift
├── Tools/                     # 辅助工具
│   └── list_input_sources.swift
├── Resources/                 # 资源文件
│   ├── config.example.json
│   └── com.user.ime-switcher.plist
├── build.sh                   # 编译快捷脚本
├── README.md
└── LICENSE
```

---

## 🔧 实现原理

- **stdout 无缓冲** — `setbuf(stdout, nil)` 确保 `kill` 也不丢日志
- **真实状态对比** — `currentInputSourceID()` 查询系统实际输入法，不依赖缓存变量
- **CJKV 验证重试** — 切换后延迟 130ms 验证，未生效则补切一次
- **输入源过滤** — `kTISCategoryKeyboardInputSource` 排除 Emoji、听写等非键盘输入
- **手动切换检测** — 监听 `kTISNotifySelectedKeyboardInputSourceChanged`，用 `lastProgrammaticTargetID` 字符串比对代替布尔标志，消除分布式通知送达时机不确定导致的竞争窗口
- **菜单栏动态渲染** — `NSMenuDelegate` 每次打开菜单时重建，实时反映当前状态
- **注释模式** — `CGEventTap` 监听按键，`.listenOnly` 模式不拦截输入；`isInCommentMode` 状态标记，切 App 自动复位
- **Tap 自动恢复** — CGEventTap 被系统因负载关闭时主动重新启用，防止注释模式静默失效

## ❓ 常见问题

**切换没反应？**  
重新运行 `swift build -c release && .build/release/list-input-sources` 核对输入法 ID 是否拼写正确。

**注释模式在不需要的应用里也生效？**  
不会。只在 `hashTriggerApps` 配置列表中的应用生效，默认空列表不触发。

**注释模式会干扰正常输入吗？**  
不会。`CGEventTap` 使用 `.listenOnly` 模式，只监听不拦截按键。密码框等安全输入场景 macOS 会自动屏蔽。

**能按网站切换输入法吗？**  
当前只支持按应用粒度。需要浏览器插件或 Accessibility 权限读取窗口标题，属于 v2 方向。

---

## 🗺️ v2 方向

- [ ] 按窗口标题 / 网页 URL 切换
- [ ] 配置文件热重载
- [ ] 偏好设置窗口

---

## 📄 许可证

MIT
