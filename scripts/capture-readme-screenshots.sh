#!/usr/bin/env bash
# README 화면 캡처: UI 테스트 러너가 Debug 앱에 샘플 Board를 만들고 창을 PNG로 저장한다(docs/images/CAPTURE.md).
# 사용법: scripts/capture-readme-screenshots.sh [출력 폴더]   (기본값 docs/images)
# 실행 중에는 키보드·마우스를 쓰지 않는다. 테스트가 입력을 합성한다.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p "${1:-docs/images}" build/logs
OUTPUT="$(cd "${1:-docs/images}" && pwd)"
DERIVED="${FIANCHETTO_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Fianchetto-verify}"
LOGS="build/logs"

RESULTS="build/readme-shots.xcresult"
rm -rf "$RESULTS"

# 테스트 러너는 앱과 같은 샌드박스라 임의 폴더에 쓸 수 없다. 첨부로 남긴 PNG를 결과 번들에서 꺼낸다.
if ! TEST_RUNNER_FIANCHETTO_README_SHOTS=1 xcodebuild -project Fianchetto.xcodeproj -scheme Fianchetto \
  -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  -resultBundlePath "$RESULTS" \
  test -only-testing:FianchettoUITests/ReadmeScreenshotTests >"$LOGS/capture-readme.log" 2>&1; then
  tail -n 40 "$LOGS/capture-readme.log" >&2
  echo "FAIL: 캡처 테스트 ($LOGS/capture-readme.log)" >&2
  exit 1
fi
EXPORT="build/readme-shots-export"
rm -rf "$EXPORT"
xcrun xcresulttool export attachments --path "$RESULTS" --output-path "$EXPORT" >/dev/null
# manifest.json: 첨부 이름(suggestedHumanReadableName) → 내보낸 파일 이름(exportedFileName).
/usr/bin/python3 -I - "$EXPORT" "$OUTPUT" <<'PY'
import json, pathlib, re, shutil, sys
export, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
count = 0
for test in json.loads((export / "manifest.json").read_text()):
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName") or ""
        if name.endswith(".png"):
            # Xcode가 붙이는 "_<번호>_<UUID>" 꼬리를 뗀다: board-tree_0_1234….png → board-tree.png
            name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(?=\.png$)", "", name)
            shutil.copyfile(export / item["exportedFileName"], output / name)
            count += 1
if count == 0:
    sys.exit("FAIL: 내보낸 PNG 첨부가 없다")
PY
echo "OK: $OUTPUT"
ls -1 "$OUTPUT"/*.png
