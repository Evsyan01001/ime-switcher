# ime-switcher — macOS 应用切换时自动切换输入法

监听前台的活跃应用变化，根据配置文件中的映射规则自动切换输入法，彻底告别手动来回切换中英文。支持菜单栏一键设置规则。

## 1. 编译

需安装 Xcode 命令行工具：`xcode-select --install`

```bash
# 编译主程序
swiftc -O \
  Config.swift \
  InputSourceManager.swift \
  AppSwitcher.swift \
  MenuController.swift \
  main.swift \
  -o ime-switcher

# 编译辅助工具（用来查看输入法 ID）
swiftc -O list_input_sources.swift -o list_input_sources
```

## 2. 查看你系统里的输入法 ID

```bash
./list_input_sources
```

输出示例：

```
ID: com.apple.keylayout.ABC
名称: ABC
---
ID: com.apple.inputmethod.SCIM.ITABC
名称: Pinyin – Simplified
---
```

把想用的输入法 ID 记下来，填到配置文件中。

## 3. 配置规则

```bash
mkdir -p ~/.config/ime-switcher
cp config.example.json ~/.config/ime-switcher/config.json
```

编辑 `~/.config/ime-switcher/config.json`：

```json
{
  "rules": {
    "com.apple.Terminal": "com.apple.keylayout.ABC",
    "com.tencent.xinWeChat": "com.apple.inputmethod.SCIM.ITABC"
  },
  "defaultInputSource": "com.apple.keylayout.ABC"
}
```

- `rules` — bundleID → 输入法 ID 映射，精确匹配优先
- `defaultInputSource` — 未匹配规则的应用使用此输入法，不填则保持不动
- 查 Bundle ID：`osascript -e 'id of app "应用名"'` 或 `mdls -name kMDItemCFBundleIdentifier /Applications/xxx.app`

## 4. 运行测试

```bash
# 长期前台运行看实时日志
./ime-switcher

# 或后台测试 10 秒自动退出
./ime-switcher &
sleep 10
kill %1
```

启动后菜单栏右上角会出现 ⌨ 图标。点击即可看到**一键设规则**子菜单，所有可选输入法一目了然。

## 5. 常见问题

- **切换没反应**：大概率输入法 ID 写错了，重新跑 `./list_input_sources` 核对
- **需要辅助功能权限吗**：只用 `NSWorkspace` + `TISSelectInputSource`，都是公开 API，不需要额外授权
- **浏览器想按网站切换输入法**：当前只支持应用粒度，v2 方向

## 6. 开机自启（可选）

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

## 项目结构

```
ime-switcher/
├── Config.swift              # 配置模型 + JSON 读写
├── InputSourceManager.swift  # 输入法查询/切换 (Carbon TIS API)
├── AppSwitcher.swift         # 应用切换主逻辑
├── MenuController.swift      # 菜单栏图标与交互
├── main.swift                # 入口文件
├── list_input_sources.swift  # 查看输入法 ID 的辅助工具
├── config.example.json
└── com.user.ime-switcher.plist
```

## 实现细节

- `setbuf(stdout, nil)` 禁用 stdout 缓冲，日志实时刷新
- `currentInputSourceID()` 查询系统当前实际输入法，避免手动切后漏切
- `kTISCategoryKeyboardInputSource` 过滤非键盘输入源（Emoji & 听写）
- `selectableInputSources()` 枚举可选输入法，菜单栏动态渲染

## v2 方向

- 按窗口标题 / 网页 URL 做更细粒度切换（需 Accessibility 权限）
- 记住每个 App 上次手动切换的输入法，自动学习规则
- 配置文件改动后自动热重载
- 悬浮指示器显示当前输入法
