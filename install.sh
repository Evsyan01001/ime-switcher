#!/bin/bash
# ime-switcher 一键安装：编译 → 打包 .app → 签名 → 注册开机自启
#
# 用法:
#   ./install.sh            安装/更新
#   ./install.sh uninstall  卸载（移除 .app、LaunchAgent，保留配置文件）
set -euo pipefail

APP_NAME="ime-switcher"
BUNDLE_ID="com.user.ime-switcher"
SIGN_IDENTITY="ime-switcher-local"
INSTALL_DIR="$HOME/Applications"
APP_DIR="$INSTALL_DIR/$APP_NAME.app"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$BUNDLE_ID.plist"
LOG_DIR="$HOME/Library/Logs"
GUI_DOMAIN="gui/$(id -u)"

cd "$(dirname "$0")"

# ── 卸载 ──
if [[ "${1:-}" == "uninstall" ]]; then
    echo "🗑️  卸载 ime-switcher..."
    launchctl bootout "$GUI_DOMAIN/$BUNDLE_ID" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    rm -rf "$APP_DIR"
    echo "✅ 已卸载（配置文件 ~/.config/ime-switcher/ 已保留）"
    exit 0
fi

# ── 1. 编译 ──
echo "🔨 编译中..."
swift build -c release 2>&1 | tail -1

# ── 2. 打包 .app ──
echo "📦 打包 $APP_DIR ..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.3</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# ── 3. 签名（固定身份 → 重打包后辅助功能权限依然有效）──
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"
    echo "🔏 已用「${SIGN_IDENTITY}」签名"
else
    codesign --force --sign - "$APP_DIR"
    echo "⚠️ 未找到签名证书「${SIGN_IDENTITY}」，已退回 ad-hoc 签名"
    echo "   （重打包后辅助功能权限可能需要重新授权）"
fi

# ── 4. LaunchAgent 开机自启 ──
echo "🚀 注册开机自启..."
mkdir -p "$PLIST_DIR" "$LOG_DIR"
launchctl bootout "$GUI_DOMAIN/$BUNDLE_ID" 2>/dev/null || true

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_DIR/Contents/MacOS/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/ime-switcher.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/ime-switcher.err</string>
</dict>
</plist>
EOF

launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH"

echo ""
echo "✅ 安装完成"
echo "   应用: $APP_DIR"
echo "   自启: $PLIST_PATH"
echo "   日志: $LOG_DIR/ime-switcher.log"
echo ""
echo "💡 注释模式 / Ghostty 窗口规则需要辅助功能权限："
echo "   系统设置 → 隐私与安全性 → 辅助功能 → 添加 $APP_DIR"
