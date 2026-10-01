#!/usr/bin/env bash
# W01-folder-structure-and-domain-imports, F-W01-1(String Catalog), W04-swiftdata-confined
# 앱 소스 폴더 구조, Domain의 import 제한, SwiftData import 범위, 한국어 String Catalog 존재를 검사한다.
# 사용법: check-structure.sh [앱 소스 루트]   (기본값: 저장소의 Fianchetto/)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)/Fianchetto}"
FOLDERS=(App Features Services Domain Persistence Platform)
CATALOG="$ROOT/Localizable.xcstrings"

failures=0
for folder in "${FOLDERS[@]}"; do
  if [[ ! -d "$ROOT/$folder" ]]; then
    echo "FAIL: 폴더 $folder 가 없다" >&2
    failures=$((failures + 1))
  fi
done

# 소스 파일이 import하는 모듈 이름. 속성(@testable 등)과 `import struct X.Y` 형태도 모듈 이름으로 본다.
imported_modules() { # imported_modules <파일>
  sed -nE 's/^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\5/p' "$1"
}

# Domain은 Foundation만 import한다.
if [[ -d "$ROOT/Domain" ]]; then
  while IFS= read -r -d '' file; do
    while IFS= read -r module; do
      if [[ "$module" != "Foundation" ]]; then
        echo "FAIL: ${file#"$ROOT"/} 가 $module 을 import한다" >&2
        failures=$((failures + 1))
      fi
    done < <(imported_modules "$file")
  done < <(find "$ROOT/Domain" -name '*.swift' -print0)
fi

# SwiftData는 Persistence와 App(조립)에서만 쓴다. @Model은 Persistence 밖으로 나가지 않는다.
for folder in Services Features Platform; do
  [[ -d "$ROOT/$folder" ]] || continue
  while IFS= read -r -d '' file; do
    if imported_modules "$file" | grep -qx 'SwiftData'; then
      echo "FAIL: ${file#"$ROOT"/} 가 SwiftData를 import한다" >&2
      failures=$((failures + 1))
    fi
  done < <(find "$ROOT/$folder" -name '*.swift' -print0)
done

if [[ ! -f "$CATALOG" ]]; then
  echo "FAIL: String Catalog Localizable.xcstrings 가 없다" >&2
  failures=$((failures + 1))
elif ! plutil -convert xml1 -o /dev/null "$CATALOG" 2>/dev/null; then
  echo "FAIL: Localizable.xcstrings 가 올바른 JSON이 아니다" >&2
  failures=$((failures + 1))
elif [[ "$(plutil -extract sourceLanguage raw -o - "$CATALOG" 2>/dev/null)" != "ko" ]]; then
  echo "FAIL: Localizable.xcstrings 의 sourceLanguage가 ko가 아니다" >&2
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  exit 1
fi
echo "OK: 폴더 구조 (${FOLDERS[*]}), Domain import, SwiftData 범위, 한국어 String Catalog"
