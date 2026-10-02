#!/usr/bin/env bash
# 저장소 전체 검증: 검사 스크립트 자체 테스트 → 구조·빌드 설정 → Debug test → Release build → entitlement.
# W01-build-and-test-zero-warnings: 컴파일러 경고 0개, Swift Testing 테스트 1개 이상 실행.
# 사용법: scripts/verify.sh            (UI 테스트 포함)
#         SKIP_UI_TESTS=1 scripts/verify.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SCHEME="Fianchetto"
PROJECT="Fianchetto.xcodeproj"
# 빌드 산출물은 ~/Documents 밖에 둔다. 저장소가 ~/Documents 아래에 있으면 UI 테스트 러너가 자기 파일을 읽을 때마다
# macOS 문서 폴더 접근 승인 창이 떠 키 입력을 가로채고 테스트가 멈춘다.
DERIVED="${FIANCHETTO_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Fianchetto-verify}"
LOGS="build/logs"
DESTINATION="platform=macOS,arch=arm64"
mkdir -p "$LOGS"

step() { printf '\n== %s\n' "$1"; }

# 컴파일러 경고(파일:줄:열: warning:)와 빌드 시스템 경고(warning: ...)를 센다.
check_warnings() { # check_warnings <로그>
  local warnings
  warnings=$(grep -E '^([^ ]+:[0-9]+:([0-9]+:)? )?warning: ' "$1" | sort -u || true)
  if [[ -n "$warnings" ]]; then
    echo "$warnings" >&2
    echo "FAIL: 경고 $(wc -l <<<"$warnings" | tr -d ' ')개 ($1)" >&2
    return 1
  fi
  echo "OK: 경고 0개 ($1)"
}

step "검사 스크립트 자체 테스트"
scripts/tests/check-scripts-test.sh

step "구조와 빌드 설정"
scripts/check-structure.sh
scripts/check-terms.sh
scripts/check-build-settings.sh

step "Debug build + test"
test_args=(-project "$PROJECT" -scheme "$SCHEME" -configuration Debug -destination "$DESTINATION"
  -derivedDataPath "$DERIVED")
if [[ "${SKIP_UI_TESTS:-0}" == 1 ]]; then
  test_args+=(-skip-testing:FianchettoUITests)
fi
if ! xcodebuild "${test_args[@]}" clean test >"$LOGS/test-debug.log" 2>&1; then
  tail -n 40 "$LOGS/test-debug.log" >&2
  echo "FAIL: xcodebuild test ($LOGS/test-debug.log)" >&2
  exit 1
fi
check_warnings "$LOGS/test-debug.log"
# 단위 테스트 target(Swift Testing suite)에서 1개 이상 통과해야 한다.
unit_passed=$(grep -Ec "^Test case 'AppFoundationTests/.*' passed" "$LOGS/test-debug.log" || true)
all_passed=$(grep -Eic "^Test case '.*' passed" "$LOGS/test-debug.log" || true)
if ((unit_passed < 1)); then
  echo "FAIL: Swift Testing 테스트가 실행되지 않았다" >&2
  exit 1
fi
# W01-launch-shows-window: UI 테스트를 건너뛰지 않았다면 실행 테스트가 통과해야 한다.
if [[ "${SKIP_UI_TESTS:-0}" != 1 ]] && ! grep -Eq "^Test Case '-\[FianchettoUITests\.LaunchTests test_W01_launchShowsSingleMainWindow\]' passed" "$LOGS/test-debug.log"; then
  echo "FAIL: 실행 UI 테스트가 통과하지 않았다" >&2
  exit 1
fi
echo "OK: 테스트 ${all_passed}개 통과"
# F-W01-1: String Catalog가 앱 target의 리소스로 처리된다(원본 언어만 있으면 문자열 표는 생성되지 않는다).
if ! grep -Eq 'xcstringstool compile .*Fianchetto\.build/.*Fianchetto/Localizable\.xcstrings' "$LOGS/test-debug.log"; then
  echo "FAIL: Localizable.xcstrings 가 앱 target에서 처리되지 않았다" >&2
  exit 1
fi
echo "OK: String Catalog가 앱 target에 포함됨"
# 테스트용 Debug 빌드에는 Xcode가 테스트 연결용 temporary-exception을 넣으므로, entitlement는 아래
# 일반 빌드(Release) 산출물에서 검사한다.

step "Release build"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" build >"$LOGS/build-release.log" 2>&1; then
  tail -n 40 "$LOGS/build-release.log" >&2
  echo "FAIL: xcodebuild Release build ($LOGS/build-release.log)" >&2
  exit 1
fi
check_warnings "$LOGS/build-release.log"
scripts/check-entitlements.sh "$DERIVED/Build/Products/Release/Fianchetto.app"
release_archs=$(lipo -archs "$DERIVED/Build/Products/Release/Fianchetto.app/Contents/MacOS/Fianchetto")
if [[ "$release_archs" != "arm64" ]]; then
  echo "FAIL: Release 실행 파일 아키텍처 '$release_archs' (기대값 arm64)" >&2
  exit 1
fi
echo "OK: Release 실행 파일 아키텍처 arm64"

printf '\nOK: 전체 검증 통과 (빌드 성공·테스트 통과. macOS 15 실기 실행은 미검증)\n'
