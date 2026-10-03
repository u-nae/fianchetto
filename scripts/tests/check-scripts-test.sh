#!/usr/bin/env bash
# 검사 스크립트 자체의 동작을 임시 fixture로 검증한다. 만든 파일은 끝에 지운다.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

passed=0
failed=0
expect() { # expect <설명> <기대 종료 코드 0|nonzero> <명령...>
  local description="$1" expected="$2"
  shift 2
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  if [[ "$expected" == 0 && $status -eq 0 ]] || [[ "$expected" == nonzero && $status -ne 0 ]]; then
    passed=$((passed + 1))
  else
    echo "FAIL: $description (종료 코드 $status)" >&2
    failed=$((failed + 1))
  fi
}

make_tree() { # make_tree <루트>
  mkdir -p "$1"/{App,Features,Services,Domain,Persistence,Platform}
  printf '{ "sourceLanguage" : "ko", "strings" : {}, "version" : "1.0" }\n' >"$1/Localizable.xcstrings"
}

# check-structure.sh
valid="$workdir/valid"
make_tree "$valid"
printf 'import Foundation\n\nstruct Snapshot {}\n' >"$valid/Domain/Snapshot.swift"
expect "구조가 맞으면 통과한다" 0 "$SCRIPTS/check-structure.sh" "$valid"

missing="$workdir/missing"
make_tree "$missing"
rmdir "$missing/Persistence"
expect "폴더 하나가 없으면 실패한다" nonzero "$SCRIPTS/check-structure.sh" "$missing"

index=0
for statement in 'import SwiftUI' '@preconcurrency import SwiftData' 'import struct AppKit.NSRect' '  import OSLog'; do
  index=$((index + 1))
  bad="$workdir/bad-$index"
  make_tree "$bad"
  printf 'import Foundation\n%s\n' "$statement" >"$bad/Domain/Rule.swift"
  expect "Domain의 '$statement' 는 실패한다" nonzero "$SCRIPTS/check-structure.sh" "$bad"
done

nested="$workdir/nested"
make_tree "$nested"
mkdir -p "$nested/Domain/Tree"
printf 'import SwiftUI\n' >"$nested/Domain/Tree/Rule.swift"
expect "Domain 하위 폴더의 금지 import도 실패한다" nonzero "$SCRIPTS/check-structure.sh" "$nested"

outside="$workdir/outside"
make_tree "$outside"
printf 'import SwiftUI\n' >"$outside/Features/View.swift"
expect "Domain 밖의 SwiftUI import는 허용한다" 0 "$SCRIPTS/check-structure.sh" "$outside"

nocatalog="$workdir/nocatalog"
make_tree "$nocatalog"
rm "$nocatalog/Localizable.xcstrings"
expect "String Catalog가 없으면 실패한다" nonzero "$SCRIPTS/check-structure.sh" "$nocatalog"

english="$workdir/english"
make_tree "$english"
printf '{ "sourceLanguage" : "en", "strings" : {}, "version" : "1.0" }\n' >"$english/Localizable.xcstrings"
expect "String Catalog 원본 언어가 ko가 아니면 실패한다" nonzero "$SCRIPTS/check-structure.sh" "$english"

broken="$workdir/broken"
make_tree "$broken"
printf '{ "sourceLanguage" : ' >"$broken/Localizable.xcstrings"
expect "String Catalog가 손상되면 실패한다" nonzero "$SCRIPTS/check-structure.sh" "$broken"

# W04-swiftdata-confined: SwiftData는 Persistence·App 폴더에서만 import한다.
for folder in Domain Services Features Platform; do
  leaked="$workdir/swiftdata-$folder"
  make_tree "$leaked"
  printf 'import Foundation\nimport SwiftData\n' >"$leaked/$folder/Store.swift"
  expect "$folder 의 SwiftData import는 실패한다" nonzero "$SCRIPTS/check-structure.sh" "$leaked"
done

attributed="$workdir/swiftdata-attributed"
make_tree "$attributed"
printf '@preconcurrency import SwiftData\n' >"$attributed/Services/Store.swift"
expect "속성이 붙은 SwiftData import도 실패한다" nonzero "$SCRIPTS/check-structure.sh" "$attributed"

allowed="$workdir/swiftdata-allowed"
make_tree "$allowed"
printf 'import SwiftData\n' >"$allowed/Persistence/Schema.swift"
printf 'import SwiftData\n' >"$allowed/App/App.swift"
expect "Persistence·App의 SwiftData import는 허용한다" 0 "$SCRIPTS/check-structure.sh" "$allowed"

# W07-terms-in-catalog: 화면 용어 검사
terms_tree() { # terms_tree <루트> <카탈로그 키 JSON> <Swift 문자열>
  make_tree "$1"
  printf '{ "sourceLanguage" : "ko", "strings" : { %s }, "version" : "1.0" }\n' "$2" >"$1/Localizable.xcstrings"
  printf 'import SwiftUI\nlet text = %s\n' "$3" >"$1/Features/View.swift"
}
required='"Board 만들기" : {}, "보관된 Board" : {}, "Bishop" : {}, "Bishop 추가" : {}, "연결 대상 변경" : {}, "Board 이름 변경" : {}, "Board 보관" : {}, "보관 해제" : {}, "Wing 추가" : {}, "웹 링크 추가" : {}, "이름 변경" : {}, "URL 변경" : {}, "Wing" : {}, "웹 링크" : {}, "위로 이동" : {}, "아래로 이동" : {}, "이동" : {}, "Bishop 제거" : {}, "Wing 제거" : {}, "웹 링크 제거" : {}, "제거" : {}, "열기" : {}, "Finder에서 보기" : {}, "다시 선택…" : {}, "상태 새로고침" : {}, "권한 필요" : {}, "대상 없음" : {}, "볼륨 연결 필요" : {}, "확인 실패" : {}, "아이콘으로 보기" : {}, "목록으로 보기" : {}, "아이콘" : {}, "기본" : {}, "문서" : {}, "데이터" : {}, "이미지" : {}, "코드" : {}, "참고" : {}, "발표" : {}, "할 일" : {}, "디자인" : {}, "Bishop · 폴더" : {}, "이력" : {}, "항목" : {}, "이력 보기" : {}, "날짜로 찾기" : {}, "현재 구성" : {}, "이 시점의 기록 없음" : {}, "이 기록을 읽을 수 없습니다" : {}, "기록을 불러오지 못했습니다" : {}, "오늘 · %@" : {}, "어제 · %@" : {}, "#%lld · %@" : {}, "#%lld에서 복원" : {}, "아이콘 변경" : {}, "과거 구성에서 만듦" : {}, "가져오기" : {}'
terms_tree "$workdir/terms-ok" "$required" '"Board 만들기"'
expect "필수 용어가 있고 금지어가 없으면 통과한다" 0 "$SCRIPTS/check-terms.sh" "$workdir/terms-ok"
terms_tree "$workdir/terms-missing" '"Board 만들기" : {}' '"Board 만들기"'
expect "필수 용어가 빠지면 실패한다" nonzero "$SCRIPTS/check-terms.sh" "$workdir/terms-missing"
index=0
for word in 'DB' 'JSON' 'bookmark' '북마크' '파일 삭제' '그룹'; do
  index=$((index + 1))
  terms_tree "$workdir/terms-catalog-$index" "$required, \"$word 오류\" : {}" '"Board 만들기"'
  expect "카탈로그의 '$word' 는 실패한다" nonzero "$SCRIPTS/check-terms.sh" "$workdir/terms-catalog-$index"
  terms_tree "$workdir/terms-source-$index" "$required" "\"$word 열기\""
  expect "화면 소스 문자열의 '$word' 는 실패한다" nonzero "$SCRIPTS/check-terms.sh" "$workdir/terms-source-$index"
done
terms_tree "$workdir/terms-identifier" "$required" '"Board 만들기"'
printf 'let bookmarkData = Data()\n' >>"$workdir/terms-identifier/Features/View.swift"
expect "문자열이 아닌 코드 식별자의 bookmark는 허용한다" 0 "$SCRIPTS/check-terms.sh" "$workdir/terms-identifier"

# check-entitlements.sh: 임시 실행 파일을 ad-hoc 서명해 entitlement 조합을 검사한다.
sign() { # sign <이름> <entitlement 키...>  → 서명된 실행 파일 경로 출력
  local name="$1"
  shift
  local binary="$workdir/$name" plist="$workdir/$name.entitlements"
  cp /usr/bin/true "$binary"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    for key in "$@"; do echo "<key>$key</key><true/>"; done
    echo '</dict></plist>'
  } >"$plist"
  codesign --force --sign - --entitlements "$plist" "$binary" >/dev/null 2>&1
  echo "$binary"
}

base=(com.apple.security.app-sandbox com.apple.security.files.user-selected.read-write com.apple.security.files.bookmarks.app-scope)
expect "필수 entitlement만 있으면 통과한다" 0 "$SCRIPTS/check-entitlements.sh" "$(sign ok "${base[@]}")"
expect "Debug 디버거 권한은 허용한다" 0 "$SCRIPTS/check-entitlements.sh" "$(sign debug "${base[@]}" com.apple.security.get-task-allow)"
expect "read-only가 함께 있으면 실패한다" nonzero "$SCRIPTS/check-entitlements.sh" \
  "$(sign readonly "${base[@]}" com.apple.security.files.user-selected.read-only)"
expect "네트워크 권한이 있으면 실패한다" nonzero "$SCRIPTS/check-entitlements.sh" \
  "$(sign network "${base[@]}" com.apple.security.network.client)"
expect "북마크 권한이 없으면 실패한다" nonzero "$SCRIPTS/check-entitlements.sh" \
  "$(sign nobookmark com.apple.security.app-sandbox com.apple.security.files.user-selected.read-write)"
expect "sandbox가 없으면 실패한다" nonzero "$SCRIPTS/check-entitlements.sh" \
  "$(sign nosandbox com.apple.security.files.user-selected.read-write com.apple.security.files.bookmarks.app-scope)"
expect "경로가 없으면 실패한다" nonzero "$SCRIPTS/check-entitlements.sh" "$workdir/does-not-exist"

# check-warnings.sh: 컴파일러·빌드 경고는 실패, XCTest 런타임 내부 진단([Internal])은 따로 보고만 한다.
log() { # log <이름> <내용>
  printf '%s\n' "$2" >"$workdir/$1.log"
  echo "$workdir/$1.log"
}
expect "경고가 없으면 통과한다" 0 "$SCRIPTS/check-warnings.sh" "$(log clean 'Build succeeded')"
expect "컴파일러 경고가 있으면 실패한다" nonzero "$SCRIPTS/check-warnings.sh" \
  "$(log compiler '/src/App.swift:12:5: warning: variable was never used')"
expect "빌드 시스템 경고가 있으면 실패한다" nonzero "$SCRIPTS/check-warnings.sh" \
  "$(log buildsystem 'warning: The app icon set has no images')"
expect "XCTest 내부 진단만 있으면 통과한다" 0 "$SCRIPTS/check-warnings.sh" \
  "$(log internal "<unknown>:0: warning: -[FianchettoUITests.BoardBrowserUITests test_W11] : [Internal] Thread running at User-interactive quality-of-service class waiting on a lower QoS thread")"
expect "XCTest 내부 진단과 컴파일러 경고가 함께 있으면 실패한다" nonzero "$SCRIPTS/check-warnings.sh" \
  "$(log mixed "<unknown>:0: warning: -[A test] : [Internal] Thread running
/src/App.swift:3:1: warning: deprecated")"
expect "테스트 이름이 붙은 다른 런타임 경고는 실패한다" nonzero "$SCRIPTS/check-warnings.sh" \
  "$(log runtime "<unknown>:0: warning: -[FianchettoUITests.LaunchTests test_W01] : Main thread checker: UI API called on a background thread")"
expect "로그 파일이 없으면 실패한다" nonzero "$SCRIPTS/check-warnings.sh" "$workdir/no-such.log"

echo "check-scripts-test: $passed passed, $failed failed"
((failed == 0))
