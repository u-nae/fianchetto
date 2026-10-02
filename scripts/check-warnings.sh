#!/usr/bin/env bash
# 빌드 로그의 경고 검사(W01 경고 0개 규칙, 0015).
# 컴파일러 경고(파일:줄:열: warning:)와 빌드 시스템 경고(warning: ...)가 하나라도 있으면 실패한다.
# 테스트 실행 중 XCTest가 내는 내부 진단("<unknown>:0: warning: -[테스트] : [Internal] ...")은 앱·빌드 경고가 아니므로
# 세지 않고 "참고"로 따로 출력한다. 그 밖의 런타임 경고(메인 스레드 검사 등)는 그대로 실패로 센다.
# 사용법: scripts/check-warnings.sh <로그>
set -euo pipefail

log="${1:?로그 경로가 필요하다}"
if [[ ! -f "$log" ]]; then
  echo "FAIL: 로그가 없다 ($log)" >&2
  exit 1
fi

internal_pattern='^<unknown>:0: warning: -\[[^]]+\] : \[Internal\] '
all=$(grep -E '^([^ ]+:[0-9]+:([0-9]+:)? )?warning: ' "$log" | sort -u || true)
internal=$(grep -E "$internal_pattern" <<<"$all" || true)
warnings=$(grep -Ev "$internal_pattern" <<<"$all" | grep -v '^$' || true)

if [[ -n "$internal" ]]; then
  echo "참고: XCTest 내부 진단 $(wc -l <<<"$internal" | tr -d ' ')개 (경고로 세지 않음, $log)"
  echo "$internal" | sed 's/^/  /'
fi
if [[ -n "$warnings" ]]; then
  echo "$warnings" >&2
  echo "FAIL: 경고 $(wc -l <<<"$warnings" | tr -d ' ')개 ($log)" >&2
  exit 1
fi
echo "OK: 경고 0개 ($log)"
