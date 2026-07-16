#!/bin/bash
set -euo pipefail

SWIFT_FILES=(
  Config.swift
  InputSourceManager.swift
  AppKeyboardCache.swift
  AppSwitcher.swift
  MenuController.swift
  HashTrigger.swift
  main.swift
)

OUTPUT="ime-switcher"
HELPER_SRC="list_input_sources.swift"
HELPER_OUT="list_input_sources"

echo "🔨 编译 ime-switcher..."

if ! xcode-select -p &>/dev/null; then
  echo "❌ 需要 Xcode Command Line Tools，请执行: xcode-select --install"
  exit 1
fi

swiftc -O "${SWIFT_FILES[@]}" -o "$OUTPUT"
echo "✅ 编译完成: $OUTPUT"

# 编译辅助工具
if [ -f "$HELPER_SRC" ]; then
  swiftc -O "$HELPER_SRC" -o "$HELPER_OUT"
  echo "✅ 编译完成: $HELPER_OUT"
fi

echo ""
echo "🚀 运行: ./$OUTPUT"
