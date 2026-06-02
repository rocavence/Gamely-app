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

# Sign with a stable self-signed identity when present (shared with Findly), so
# macOS keeps any TCC grants across rebuilds instead of resetting them like an
# ad-hoc signature does. Falls back to ad-hoc otherwise.
SIGN_IDENTITY="Findly Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "${SIGN_IDENTITY}"; then
  echo "→ codesign with ${SIGN_IDENTITY}"
  codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp=none "${APP_DIR}"
else
  echo "→ ad-hoc codesign (no '${SIGN_IDENTITY}' identity found)"
  codesign --force --deep --sign - "${APP_DIR}"
fi

echo
echo "Done. Open with:  open ${APP_DIR}"
