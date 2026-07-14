# ime-switcher — macOS 应用切换时自动切换输入法

原理:监听 `NSWorkspace` 的"前台应用切换"通知,根据你配置的 `bundleID -> 输入法ID` 映射表,调用 Carbon 的 `TISSelectInputSource` 切换输入法。纯 Swift 脚本,不需要 Xcode 工程,`swiftc` 直接编译即可。

## 1. 编译

在你的 Mac 上(需要已安装 Xcode 命令行工具,`xcode-select --install`):

```bash
# 编译主程序
swiftc -O main.swift -o ime-switcher

# 编译辅助工具(用来查看输入法 ID)
swiftc -O list_input_sources.swift -o list_input_sources
```

## 2. 查看你系统里的输入法 ID

```bash
./list_input_sources
```

会打印类似:

```
ID: com.apple.keylayout.ABC
名称: ABC
---
ID: com.apple.inputmethod.SCIM.ITABC
名称: 拼音 - 简体
---
```

把你想用的输入法 ID 记下来,填到 config.json 里。

## 3. 配置规则

```bash
mkdir -p ~/.config/ime-switcher
cp config.example.json ~/.config/ime-switcher/config.json
```

编辑 `~/.config/ime-switcher/config.json`:

```json
{
  "rules": {
    "com.apple.Terminal": "com.apple.keylayout.ABC",
    "com.googlecode.iterm2": "com.apple.keylayout.ABC"
  },
  "defaultInputSource": null
}
```

- `rules` 的 key 是应用的 Bundle ID,value 是要切换到的输入法 ID
- 查某个 App 的 Bundle ID:`osascript -e 'id of app "微信"'` 或者 `mdls -name kMDItemCFBundleIdentifier /Applications/xxx.app`
- `defaultInputSource`:没匹配到规则时切到的输入法,不需要就填 `null`

## 4. 运行测试

先确保配置文件里至少有一条规则（比如给 Terminal 配上）。然后可以直接临时测试：

```bash
# 后台运行 10 秒后自动停止，不影响长期使用
./ime-switcher &
sleep 10
kill %1
```

或者长期前台运行看完整日志：

```bash
./ime-switcher
```

日志会实时打印在终端里（stdout 已禁用缓冲，`kill` 也不会丢日志）。保持终端开着，切到已配置的应用试试，观察是否按预期切换。

## 5. 常见问题

- **切换没反应**:大概率是输入法 ID 写错了,重新跑一遍 `list_input_sources` 核对拼写。
- **需要辅助功能权限吗**:这个 MVP 只用了 `NSWorkspace`(读取前台应用)和 `TISSelectInputSource`(切换输入法),这两个都是公开 API,一般不需要额外申请"辅助功能"权限。如果之后要做"根据网页 URL / 窗口标题"这种更细粒度的切换,那需要用 Accessibility API,才会要权限。
- **同一个 App 里想区分场景**(比如浏览器切到某网站才用英文):这个 MVP 只按 App 粒度切换,做不到网页级别,需要额外接浏览器插件或 Accessibility 读取窗口标题,是个 v2 方向。

## 6. 开机自启(可选)

```bash
# 把编译好的可执行文件放到一个固定路径
sudo cp ime-switcher /usr/local/bin/ime-switcher

# 安装 LaunchAgent
cp com.user.ime-switcher.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.ime-switcher.plist
```

停止/卸载:

```bash
launchctl bootout gui/$(id -u)/com.user.ime-switcher
rm ~/Library/LaunchAgents/com.user.ime-switcher.plist
```

`KeepAlive` 为 `true`，进程异常退出后 launchd 会自动重启。日志在 `/tmp/ime-switcher.log` 和 `/tmp/ime-switcher.err`。

## 实现细节

- 代码开头有 `setbuf(stdout, nil)` 禁用 stdout 缓冲，确保日志实时刷新，即使用 `kill` 终止进程也不丢日志。
- 用 `lastSwitchedID` 记录上次切换的输入法 ID，相同目标输入法不再重复调用 `TISSelectInputSource`。

## 后续可以加的功能(v2 方向)

- 菜单栏图标(用 `NSStatusItem`)显示当前状态、快速改配置
- 按窗口标题 / 网页 URL 做更细粒度切换(需要 Accessibility 权限)
- 记住每个 App 上次手动切换的输入法,自动学习规则
- 配置文件改动后自动热重载(用 `DispatchSource` 监听文件变化)
