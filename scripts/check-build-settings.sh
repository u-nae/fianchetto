#!/usr/bin/env bash
# W01-build-settings-fixed (F-W01-2 반영)
# 모든 target의 Debug·Release 확정 빌드 설정과, 외부 패키지가 테스트 전용 허용 목록뿐인지(0028) 검사한다.
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

# 외부 패키지: 0028이 허용한 테스트 전용 패키지만 둔다. 앱 target은 패키지에 의존하지 않는다.
ALLOWED_PACKAGES=("https://github.com/pointfreeco/swift-snapshot-testing")
if grep -q 'XCLocalSwiftPackageReference' "$PROJECT/project.pbxproj"; then
  echo "FAIL: 로컬 Swift Package 의존성이 있다" >&2
  failures=$((failures + 1))
fi
while IFS= read -r url; do
  allowed=0
  for ok in "${ALLOWED_PACKAGES[@]}"; do [[ "$url" == "$ok" ]] && allowed=1; done
  if ((allowed == 0)); then
    echo "FAIL: 허용하지 않은 Swift Package가 있다: $url" >&2
    failures=$((failures + 1))
  fi
done < <(grep -Eo 'repositoryURL = "[^"]+"' "$PROJECT/project.pbxproj" | sed -E 's/repositoryURL = "([^"]+)"/\1/')
# 앱 target(name = Fianchetto;) 블록의 packageProductDependencies는 비어 있어야 한다.
app_deps=$(awk '/isa = PBXNativeTarget;/{block=""; inblock=1} inblock{block=block $0 "\n"} inblock && /^\t\t};/{ if (block ~ /name = Fianchetto;/) print block; inblock=0 }' "$PROJECT/project.pbxproj" \
  | awk '/packageProductDependencies = \(/{flag=1; next} flag && /\);/{flag=0} flag' | grep -c . || true)
if [[ "$app_deps" != "0" ]]; then
  echo "FAIL: 앱 target이 Swift Package에 의존한다" >&2
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  exit 1
fi
echo "OK: 빌드 설정 (${TARGETS[*]} × ${CONFIGURATIONS[*]}), 외부 패키지는 테스트 전용 허용 목록만(0028)"
