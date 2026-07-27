# 图标导出说明

## 文件清单

```
AppIcon.icns                # app 图标（可直接用，Fredoka 字体 + 全出血）
AppIcon-1024-fullbleed.png  # 1024px 全出血母版（四角填满，系统裁圆角）
AppIcon-1024-preview.png    # 1024px 预览图（透明圆角，仅预览用）
MenuBarIcon.png             # 菜单栏图标 22x22，透明背景
MenuBarIcon@2x.png          # 44x44
MenuBarIcon@3x.png          # 66x66
master_icon.svg             # app 图标源文件（矢量，可编辑）
menubar_icon.svg            # 菜单栏图标源文件（矢量，可编辑）
```

## 字体说明

`AppIcon.icns` 已使用设计稿的 **Fredoka**（wght 600）渲染，通过 Chrome headless 加载 Google Fonts 完成。`master_icon.svg` 里已写入 `@import` 和 `font-family="'Fredoka'"`，本地直接打开 SVG 预览需要系统装有 Fredoka，否则会回退到默认无衬线字体。

菜单栏图标（`MenuBarIcon*.png`）没有文字，与字体无关。

## 全出血说明（重要）

macOS 对四角透明的图标会自动缩小并垫灰色圆角底板。因此 icns 必须使用**全出血**版本：整个 1024 画布不透明（四角填满黑色），由系统按 squircle 裁切。改设计后务必走下面的重新生成流程，不要直接把透明圆角的预览图塞进 iconset。

## 集成到项目

### 1. app 图标

`AppIcon.icns` 已拷贝到 `Resources/`。`install.sh` 打包时会拷进 `.app/Contents/Resources/`，`Info.plist` 已配置：

```xml
<key>CFBundleIconFile</key>
<string>AppIcon</string>
```

### 2. 菜单栏图标

`MenuBarIcon*.png` 已拷贝到 `Resources/` 并由 `install.sh` 打包。`MenuController.swift` 加载并标记为**模板图像**（系统自动适配深色/浅色菜单栏）：

```swift
if let iconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
   let image = NSImage(contentsOf: iconURL) {
    image.isTemplate = true  // 关键：标记为模板图像，系统自动反色
    statusItem.button?.image = image
}
```

`@2x` / `@3x` 不需要在代码里显式引用——文件名符合 `MenuBarIcon.png` / `MenuBarIcon@2x.png` / `MenuBarIcon@3x.png` 规范时，系统会按屏幕分辨率自动选择。

## 改设计后重新生成

```bash
# 1. Chrome headless 渲染 SVG（联网加载 Fredoka）
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1024,1024 --default-background-color=00000000 \
  --virtual-time-budget=8000 \
  --screenshot=/tmp/icon-1024.png "file://$PWD/master_icon.svg"

# 2. 合成全出血（四角填黑）→ AppIcon-1024-fullbleed.png

# 3. 生成各尺寸并打包 icns
mkdir -p AppIcon.iconset
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
            "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "$px" "$px" AppIcon-1024-fullbleed.png --out "AppIcon.iconset/$name.png"
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns

# 4. 替换 Resources/AppIcon.icns，跑 install.sh，然后刷新图标缓存
touch ~/Applications/ime-switcher.app
lsregister -f ~/Applications/ime-switcher.app
killall Finder; killall Dock
```
