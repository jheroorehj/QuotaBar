#!/usr/bin/env bash
# QuotaBar.app 번들을 만든다. (macOS 전용)
#
#   ./scripts/build-app.sh             # build/QuotaBar.app 생성
#   ./scripts/build-app.sh --install   # 생성 후 /Applications 로 복사하고 실행
#   UNIVERSAL=1 ./scripts/build-app.sh # Apple Silicon + Intel 유니버설 바이너리
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname)" != "Darwin" ]]; then
  echo "macOS 에서만 앱 번들을 만들 수 있습니다." >&2
  exit 1
fi

INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

BUILD_ARGS=(-c release --product QuotaBar)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "▶ swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

APP="build/QuotaBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/QuotaBar" "$APP/Contents/MacOS/QuotaBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# 앱 아이콘(AppIcon.icns, scripts/make-app-icon.py 로 생성)과 메뉴바(icons_QuotaBar.icns)·서비스 아이콘. 실행 중에는 AppIcons 가 파일 이름으로 찾는다.
find Sources/Icons -maxdepth 1 -type f \( -name '*.icns' -o -name '*.svg' -o -name '*.png' \) \
  -exec cp {} "$APP/Contents/Resources/" \;

# 로컬 실행용 ad-hoc 서명 (개발자 인증서 불필요)
codesign --force --sign - --timestamp=none "$APP"
echo "✔ $APP"

if [[ "$INSTALL" == "1" ]]; then
  TARGET="/Applications/QuotaBar.app"
  osascript -e 'tell application "QuotaBar" to quit' >/dev/null 2>&1 || true
  rm -rf "$TARGET"
  cp -R "$APP" "$TARGET"
  echo "✔ $TARGET 설치"
  open "$TARGET"
fi
