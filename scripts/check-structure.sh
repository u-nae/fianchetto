#!/usr/bin/env bash
# W01-folder-structure-and-domain-imports, F-W01-1(String Catalog)
# 앱 소스 폴더 구조, Domain의 import 제한, 한국어 String Catalog 존재를 검사한다.
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

# Domain은 Foundation만 import한다. 속성(@testable 등)과 `import struct X.Y` 형태도 모듈 이름으로 본다.
if [[ -d "$ROOT/Domain" ]]; then
  while IFS= read -r -d '' file; do
    while IFS= read -r module; do
      if [[ "$module" != "Foundation" ]]; then
        echo "FAIL: ${file#"$ROOT"/} 가 $module 을 import한다" >&2
        failures=$((failures + 1))
      fi
    done < <(sed -nE 's/^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\5/p' "$file")
  done < <(find "$ROOT/Domain" -name '*.swift' -print0)
fi

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
echo "OK: 폴더 구조 (${FOLDERS[*]}), Domain import, 한국어 String Catalog"
