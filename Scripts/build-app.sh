#!/bin/bash
# Build Gamely as a macOS .app bundle. Output: build/Gamely.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Gamely"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

echo "→ swift build (release)"
swift build -c release

echo "→ assembling bundle at ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "${RES_DIR}/AppIcon.icns"
fi
# Bundle every localization (.lproj) so NSLocalizedString can load it at runtime.
for lproj in Resources/*.lproj; do
  cp -R "$lproj" "${RES_DIR}/"
done
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "→ ad-hoc codesign"
codesign --force --deep --sign - "${APP_DIR}"

echo
echo "Done. Open with:  open ${APP_DIR}"
