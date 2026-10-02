#!/usr/bin/env bash
# W07-terms-in-catalog, W08-menu-command(Bishop 추가), W09-commands(연결 대상 변경), W10-commands-no-delete(이름 변경·보관), W11-commands(그룹·웹 링크·이름·URL)
# 화면 용어(0006)가 String Catalog에 있고, 화면 문구(카탈로그와 Features·App의 문자열 리터럴)에 구현 용어가 없는지 검사한다.
# 사용법: check-terms.sh [앱 소스 루트]   (기본값: 저장소의 Fianchetto/)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)/Fianchetto}"
CATALOG="$ROOT/Localizable.xcstrings"
REQUIRED=("Board 만들기" "보관된 Board" "Bishop" "Bishop 추가" "연결 대상 변경" "Board 이름 변경" "Board 보관" "보관 해제" "그룹 추가" "웹 링크 추가" "이름 변경" "URL 변경" "그룹" "웹 링크" "위로 이동" "아래로 이동" "이동" "Bishop 제거" "그룹 제거" "웹 링크 제거" "제거" "열기" "Finder에서 보기")
# 대소문자를 구분하는 금지어와 구분하지 않는 금지어.
FORBIDDEN_EXACT=("DB" "JSON")
FORBIDDEN_ANYCASE=("bookmark" "북마크" "파일 삭제")

failures=0
if [[ ! -f "$CATALOG" ]]; then
  echo "FAIL: Localizable.xcstrings 가 없다" >&2
  exit 1
fi

for term in "${REQUIRED[@]}"; do
  if ! plutil -extract "strings.$term" json -o /dev/null "$CATALOG" 2>/dev/null; then
    echo "FAIL: String Catalog에 \"$term\" 가 없다" >&2
    failures=$((failures + 1))
  fi
done

# 화면 문구 후보: 카탈로그 전체와 Features·App 소스의 문자열 리터럴.
texts=$(
  cat "$CATALOG"
  for folder in Features App; do
    [[ -d "$ROOT/$folder" ]] || continue
    find "$ROOT/$folder" -name '*.swift' -print0 | xargs -0 grep -ho '"[^"]*"' 2>/dev/null || true
  done
)
for word in "${FORBIDDEN_EXACT[@]}"; do
  if grep -q -- "$word" <<<"$texts"; then
    echo "FAIL: 화면 문구에 구현 용어 \"$word\" 가 있다" >&2
    failures=$((failures + 1))
  fi
done
for word in "${FORBIDDEN_ANYCASE[@]}"; do
  if grep -qi -- "$word" <<<"$texts"; then
    echo "FAIL: 화면 문구에 금지 표현 \"$word\" 가 있다" >&2
    failures=$((failures + 1))
  fi
done

if ((failures > 0)); then
  exit 1
fi
echo "OK: 화면 용어 (${REQUIRED[*]}), 구현 용어·금지 표현 없음"
