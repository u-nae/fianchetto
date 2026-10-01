#!/usr/bin/env bash
# W01-build-settings-fixed (F-W01-2 반영)
# 모든 target의 Debug·Release 확정 빌드 설정과 외부 패키지 0개를 검사한다.
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT="Fianchetto.xcodeproj"
TARGETS=(Fianchetto FianchettoTests FianchettoUITests)
CONFIGURATIONS=(Debug Release)
EXPECTED=(
  "SWIFT_VERSION=6.0"
  "SWIFT_STRICT_CONCURRENCY=complete"
  "MACOSX_DEPLOYMENT_TARGET=15.0"
  "ARCHS=arm64"
)

if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  echo "FAIL: $PROJECT 가 없다" >&2
  exit 1
fi

failures=0
for configuration in "${CONFIGURATIONS[@]}"; do
  for target in "${TARGETS[@]}"; do
    if ! settings=$(xcodebuild -project "$PROJECT" -target "$target" -configuration "$configuration" \
      -showBuildSettings 2>/dev/null); then
      echo "FAIL: $target/$configuration 빌드 설정을 읽을 수 없다" >&2
      failures=$((failures + 1))
      continue
    fi
    for pair in "${EXPECTED[@]}"; do
      key="${pair%%=*}"
      expected="${pair#*=}"
      actual=$(awk -v key="$key" '$1 == key && $2 == "=" { sub(/^[^=]*= /, ""); print; exit }' <<<"$settings")
      if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $target/$configuration $key = '${actual}' (기대값 '$expected')" >&2
        failures=$((failures + 1))
      fi
    done
  done
done

if grep -Eq 'XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference' "$PROJECT/project.pbxproj"; then
  echo "FAIL: Swift Package 의존성이 있다" >&2
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  exit 1
fi
echo "OK: 빌드 설정 (${TARGETS[*]} × ${CONFIGURATIONS[*]}), 외부 패키지 0개"
