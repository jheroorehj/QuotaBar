#!/usr/bin/env bash
# 배포용 DMG 를 만든다. (macOS 전용)
# 열면 QuotaBar.app 과 "응용 프로그램" 바로가기가 보이고, 앱을 끌어다 놓으면 설치된다.
#
#   ./scripts/build-dmg.sh             # build/QuotaBar-<버전>.dmg 생성
#   UNIVERSAL=1 ./scripts/build-dmg.sh # Intel Mac 에서도 실행되는 유니버설 바이너리로
#
# 앱은 ad-hoc 서명이라 다른 Mac 에서 처음 열 때 Gatekeeper 가 막는다 (여는 방법은 DMG 안의 안내 파일 — 원본은 Resources/dmg-readme.txt).
# 경고 없이 열리게 하려면 Developer ID 서명·공증이 필요하다.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP="build/QuotaBar.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/QuotaBar-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# ditto 는 서명에 필요한 확장 속성을 그대로 옮긴다.
ditto "$APP" "$STAGE/QuotaBar.app"
ln -s /Applications "$STAGE/Applications"
# 만든 사람의 정보가 배포판에 섞이지 않았는지 확인한다 (계정 이름, 홈 폴더 경로, git 사용자 정보).
leaks=""
for needle in "$(id -un)" "$HOME" "$(git config user.name 2>/dev/null || true)" "$(git config user.email 2>/dev/null || true)"; do
  [ -n "$needle" ] || continue
  if find "$STAGE/QuotaBar.app" -type f -exec sh -c 'strings -a "$1" | grep -qiF -- "$2"' _ {} "$needle" \; -print | grep -q .; then
    leaks="$leaks $needle"
  fi
done
if [ -n "$leaks" ]; then
  echo "✘ 배포판에 개인 정보가 들어 있습니다:$leaks" >&2
  exit 1
fi

# 받는 사람을 위한 안내: 설치, 내 계정 연동, 개인정보.
cp Resources/dmg-readme.txt "$STAGE/먼저 읽어 주세요.txt"

rm -f "$DMG"
echo "▶ hdiutil create $DMG"
hdiutil create -volname "QuotaBar" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "✔ $DMG"
