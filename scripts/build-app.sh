#!/bin/zsh
# 建置 Release 版 Gamely（本機簽章，未公證），打包成發版用的 zip。
# 用法：scripts/build-app.sh [--install]   輸出：dist/Gamely-<版本>.zip
#   --install  順便換掉「應用程式」裡的 Gamely（先正常結束正在執行的版本，讓它還原熱角）
# 建置輸出放在 build/xcode.noindex：資料夾名稱結尾是 .noindex，Spotlight 不會把裡面的 app
# 當成另一份 Gamely 列進搜尋結果；dist 也只放 zip，不放 .app。
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
python3 scripts/site/build.py   # 官網版本號跟著 project.yml
xcodebuild -project Gamely.xcodeproj -scheme Gamely -configuration Release \
  -derivedDataPath build/xcode.noindex build | grep -E "error:|BUILD" || true

APP=build/xcode.noindex/Build/Products/Release/Gamely.app
[[ -d "$APP" ]] || { echo "建置失敗：找不到 $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p dist
rm -f "dist/Gamely-${VERSION}.zip"
ditto -c -k --keepParent "$APP" "dist/Gamely-${VERSION}.zip"
echo "完成：dist/Gamely-${VERSION}.zip"
shasum -a 256 "dist/Gamely-${VERSION}.zip"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app id "com.gamely.app"' 2>/dev/null || true
  for _ in {1..10}; do pgrep -f /Applications/Gamely.app >/dev/null || break; sleep 0.5; done
  rm -rf /Applications/Gamely.app
  ditto "$APP" /Applications/Gamely.app
  open /Applications/Gamely.app
  echo "已安裝並開啟：/Applications/Gamely.app ${VERSION}"
fi
