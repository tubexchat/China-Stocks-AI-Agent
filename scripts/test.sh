#!/usr/bin/env bash
# 运行 Axblade 单元测试,只打印测试结果与编译错误。
set -uo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild test \
  -project Axblade.xcodeproj \
  -scheme Axblade \
  -destination 'platform=macOS,arch=arm64' 2>&1 \
  | grep -E "error:|warning: (unused|variable|never)|Test Case .* (passed|failed)|Executed [0-9]+ test|\*\* TEST (SUCCEEDED|FAILED) \*\*|\*\* BUILD FAILED \*\*"
exit "${PIPESTATUS[0]}"
