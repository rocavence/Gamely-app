#!/bin/zsh
# 建置 Release 版 Gamely.app（本機簽章，未公證）。
# 用法：scripts/build-app.sh   輸出：dist/Gamely.app
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Gamely.xcodeproj -scheme Gamely -configuration Release \
  -derivedDataPath build build | grep -E "error:|BUILD" || true

APP=build/Build/Products/Release/Gamely.app
[[ -d "$APP" ]] || { echo "建置失敗：找不到 $APP" >&2; exit 1; }
rm -rf dist && mkdir -p dist
# 建置輸出不讓 Spotlight 索引，搜尋 App 時只會找到「應用程式」裡的 Gamely
touch build/.metadata_never_index dist/.metadata_never_index
cp -R "$APP" dist/
echo "完成：dist/Gamely.app"
