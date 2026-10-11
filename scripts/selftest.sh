#!/bin/zsh
# 端對端自我測試：實際操作 app 的控制器與選單，改的是測試用的偏好設定網域，
# 不會重啟 Dock，也不碰你真正的熱角。
# 用法：scripts/selftest.sh [項目]   紀錄在 build/selftest/log，設定頁截圖在 build/selftest/shots
# 項目：hotcorners usersetting recovery restart debounce menu windows（不填就全跑）
# 換語言或外觀：GAMELY_LANG=ja GAMELY_APPEARANCE=dark scripts/selftest.sh windows
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/selftest
rm -rf "$OUT" && mkdir -p "$OUT/shots"

xcodegen generate --quiet
xcodebuild -project Gamely.xcodeproj -scheme Gamely -configuration Debug \
  -derivedDataPath build/xcode.noindex build | grep -E "error:|BUILD FAILED" || true
APP=build/xcode.noindex/Build/Products/Debug/Gamely.app/Contents/MacOS/Gamely

APPEARANCE=()
[[ -n "${GAMELY_APPEARANCE:-}" ]] && APPEARANCE=(-Gamely.appearance "$GAMELY_APPEARANCE")
GAMELY_SHOTS="$PWD/$OUT/shots" GAMELY_SELFTEST="${1:-all}" "$APP" -AppleLanguages "(\"${GAMELY_LANG:-zh-Hant}\")" "${APPEARANCE[@]}" > "$OUT/log" 2>&1 &
PID=$!
for _ in {1..30}; do
  sleep 1
  kill -0 $PID 2>/dev/null || break
done
kill $PID 2>/dev/null || true
grep -E "PASS|FAIL|SELFTEST" "$OUT/log"
grep -q "SELFTEST OK" "$OUT/log"
