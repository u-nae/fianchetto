#!/usr/bin/env bash
# W01-sandbox-entitlements (F-W01-3 반영)
# 서명된 앱의 com.apple.security.* entitlement가 허용 목록과 정확히 맞는지 검사한다.
# 사용법: check-entitlements.sh <서명된 앱 번들 또는 실행 파일 경로>
set -euo pipefail

if [[ $# -ne 1 || ! -e "$1" ]]; then
  echo "사용법: $0 <서명된 앱 번들 또는 실행 파일 경로>" >&2
  exit 2
fi
APP="$1"

REQUIRED=(
  com.apple.security.app-sandbox
  com.apple.security.files.user-selected.read-write
  com.apple.security.files.bookmarks.app-scope
)
# Xcode가 Debug 서명에 넣는 디버거 연결 권한만 추가로 허용한다.
OPTIONAL=(com.apple.security.get-task-allow)

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
plist="$workdir/entitlements.plist"

if ! codesign -d --entitlements - --xml "$APP" >"$plist" 2>/dev/null || [[ ! -s "$plist" ]]; then
  echo "FAIL: $APP 의 entitlement를 읽을 수 없다" >&2
  exit 1
fi

keys=$(/usr/libexec/PlistBuddy -c Print "$plist" | awk -F' = ' '/^    [^ ]/ { gsub(/^ +/, "", $1); print $1 }')

failures=0
for key in "${REQUIRED[@]}"; do
  value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true)
  if [[ "$value" != "true" ]]; then
    echo "FAIL: 필수 entitlement $key 가 true가 아니다 ('$value')" >&2
    failures=$((failures + 1))
  fi
done

while IFS= read -r key; do
  [[ -z "$key" || "$key" != com.apple.security.* ]] && continue
  allowed=false
  for candidate in "${REQUIRED[@]}" "${OPTIONAL[@]}"; do
    [[ "$key" == "$candidate" ]] && allowed=true
  done
  if [[ "$allowed" != true ]]; then
    echo "FAIL: 허용하지 않은 entitlement $key" >&2
    failures=$((failures + 1))
  fi
done <<<"$keys"

if ((failures > 0)); then
  exit 1
fi
echo "OK: entitlement (${REQUIRED[*]})"
