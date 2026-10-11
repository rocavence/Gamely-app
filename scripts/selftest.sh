#!/bin/zsh
# 端對端自我測試：實際操作 app 的控制器與選單，改的是測試用的偏好設定網域，
# 不會重啟 Dock，也不碰你真正的熱角。
# 用法：scripts/selftest.sh [hotcorners|debounce|menu]   紀錄在 build/selftest/log
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/selftest
rm -rf "$OUT" && mkdir -p "$OUT"

xcodegen generate --quiet
xcodebuild -project Gamely.xcodeproj -scheme Gamely -configuration Debug \
  -derivedDataPath build build | grep -E "error:|BUILD FAILED" || true
APP=build/Build/Products/Debug/Gamely.app/Contents/MacOS/Gamely

GAMELY_SELFTEST="${1:-all}" "$APP" -AppleLanguages "(\"${GAMELY_LANG:-zh-Hant}\")" > "$OUT/log" 2>&1 &
PID=$!
for _ in {1..30}; do
  sleep 1
  kill -0 $PID 2>/dev/null || break
done
kill $PID 2>/dev/null || true
grep -E "PASS|FAIL|SELFTEST" "$OUT/log"
grep -q "SELFTEST OK" "$OUT/log"
