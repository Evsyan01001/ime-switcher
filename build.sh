#!/bin/bash
set -euo pipefail

echo "🔨 编译 ime-switcher..."
swift build -c release

echo ""
echo "✅ 编译完成"
echo "📦 主程序: $(swift build -c release --show-bin-path)/ime-switcher"
echo "📦 辅助工具: $(swift build -c release --show-bin-path)/list-input-sources"
echo ""
echo "🚀 运行: $(swift build -c release --show-bin-path)/ime-switcher"
