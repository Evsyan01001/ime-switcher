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

## ✨ 功能

| 功能 | 说明 |
|------|------|
| 🔄 **自动切换** | 切换应用时根据规则自动切换输入法 |
| 🧠 **输入法记忆** | 手动切一次输入法，下次自动恢复 |
| 🎯 **默认兜底** | 未配置规则的应用可以指定默认输入法 |
| 🖱️ **菜单栏设置** | 点击 ⌨ 图标，一键为当前应用指定输入法 |
| ✅ **CJKV 可靠切换** | 验证重试机制，确保中日韩越输入法切换生效 |
| 💬 **注释模式** | 在配置的 App 中按 `#` 自动切拼音，按 Enter 自动回英文 |

## 📦 安装

### 前置条件

```bash
xcode-select --install
```

### 编译

```bash
git clone https://github.com/Evsyan01001/ime-switcher.git
cd ime-switcher

swiftc -O \
  Config.swift \
  InputSourceManager.swift \
  AppKeyboardCache.swift \
  AppSwitcher.swift \
  MenuController.swift \
  HashTrigger.swift \
  main.swift \
  -o ime-switcher

# 辅助工具：查看你的输入法 ID
swiftc -O list_input_sources.swift -o list_input_sources
```

### 首次配置

```bash
# 1. 查看系统里有哪些输入法
./list_input_sources

# 2. 创建配置文件
mkdir -p ~/.config/ime-switcher
cp config.example.json ~/.config/ime-switcher/config.json

# 3. 编辑配置
vim ~/.config/ime-switcher/config.json
```

## ⚙️ 配置文件

```json
{
  "rules": {
    "com.apple.Terminal": "com.apple.keylayout.ABC",
    "com.tencent.xinWeChat": "com.apple.inputmethod.SCIM.ITABC"
  },
  "defaultInputSource": null,
  "hashTriggerApps": [
    "com.microsoft.VSCode",
    "com.apple.Terminal"
  ]
}
```

| 字段 | 说明 |
|------|------|
| `rules` | bundleID → 输入法 ID 映射，精确匹配优先 |
| `defaultInputSource` | 未匹配的应用使用此输入法，不填则保持不动 |
| `hashTriggerApps` | 在此列表的 App 中按 `#` 自动切拼音写注释 |

**查 Bundle ID：**
```bash
osascript -e 'id of app "微信"'
mdls -name kMDItemCFBundleIdentifier /Applications/xxx.app
```

## 🚀 使用

```bash
# 运行（菜单栏出现 ⌨ 图标）
./ime-switcher

# 后台测试
./ime-switcher &
```

启动后：
1. 点击菜单栏 ⌨ 图标
2. 选择「将「当前应用」设为」→ 选择输入法
3. 切换到该应用时自动使用选中的输入法

### 输入法记忆

手动切换输入法后，程序会自动记住你的选择。下次切回这个 App 时恢复你上次用的输入法。

菜单栏 → 「忘记这个 App 的偏好」可以清除记忆，恢复配置规则。

### 注释模式（`#` 触发拼音）

在 `hashTriggerApps` 配置的 App（如 VSCode、Terminal）中：

1. 按 <kbd>#</kbd> → 自动切换到拼音输入法
2. 写中文注释
3. 按 <kbd>Enter</kbd> → 自动切回英文

> **需要额外权限：** 首次使用需在 **系统设置 → 隐私与安全性 → 辅助功能（或输入监控）** 中添加 `ime-switcher` 可执行文件。

## 🗂️ 项目结构

```
ime-switcher/
├── Config.swift              # 配置模型 + JSON 读写
├── InputSourceManager.swift  # 输入法查询/切换 (Carbon TIS API)
├── AppKeyboardCache.swift    # 输入法记忆（手动切换自动记录）
├── AppSwitcher.swift         # 应用切换主逻辑
├── MenuController.swift      # 菜单栏图标与交互
├── HashTrigger.swift         # # 触发拼音 + 注释模式
├── main.swift                # 入口文件
├── list_input_sources.swift  # 查看输入法 ID 的辅助工具
├── config.example.json       # 配置示例
└── com.user.ime-switcher.plist  # 开机自启配置
```

## 🔄 开机自启（可选）

```bash
sudo cp ime-switcher /usr/local/bin/ime-switcher
cp com.user.ime-switcher.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.ime-switcher.plist
```

停止 / 卸载：

```bash
launchctl bootout gui/$(id -u)/com.user.ime-switcher
rm ~/Library/LaunchAgents/com.user.ime-switcher.plist
```

`KeepAlive` 为 `true`，异常退出后自动重启。日志在 `/tmp/ime-switcher.log` 和 `/tmp/ime-switcher.err`。

## 🔧 实现细节

- **stdout 无缓冲** — `setbuf(stdout, nil)` 确保 `kill` 也不丢日志
- **真实状态对比** — `currentInputSourceID()` 查询系统实际输入法，不依赖缓存变量
- **CJKV 验证重试** — 切换后延迟 130ms 验证，未生效则补切一次
- **输入源过滤** — `kTISCategoryKeyboardInputSource` 排除 Emoji、听写等非键盘输入
- **手动切换检测** — 监听 `kTISNotifySelectedKeyboardInputSourceChanged`，自动记录 App 偏好
- **菜单栏动态渲染** — `NSMenuDelegate` 每次打开菜单时重建，实时反映当前状态
- **注释模式** — `CGEventTap` 监听 `#` 按键，`isInCommentMode` 状态标记，切 App 自动复位

## ❓ 常见问题

**切换没反应？**  
重新跑 `./list_input_sources` 核对输入法 ID 是否拼写正确。

**需要什么权限？**  
基础功能（自动切换/菜单栏/输入法记忆）**不需要任何权限**。注释模式（`#` 触发拼音）需要「辅助功能」或「输入监控」权限。

**`#` 触发拼音在不需要的应用里也生效？**  
只在 `hashTriggerApps` 配置列表中的应用生效，默认空列表不触发。

**注释模式会干扰正常输入吗？**  
不会。`CGEventTap` 使用 `.listenOnly` 模式，只监听不拦截按键。密码框等安全输入场景 macOS 会自动屏蔽。

**能按网站切换输入法吗？**  
当前只支持按应用粒度。需浏览器插件或 Accessibility 权限读取窗口标题，属于 v2 方向。

## 🗺️ v2 方向

- [ ] 按窗口标题 / 网页 URL 切换
- [ ] 配置文件热重载
- [ ] 偏好设置窗口

## 📄 许可证

MIT
