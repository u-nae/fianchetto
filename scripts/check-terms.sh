#!/usr/bin/env bash
# W07-terms-in-catalog, W08-menu-command(Bishop 추가), W09-commands(연결 대상 변경), W10-commands-no-delete(이름 변경·보관), W11-commands(Wing·웹 링크·이름·URL), W29-catalog(아이콘·용도·Bishop · 폴더), W17-catalog(이력 탭 문구), W18-catalog(과거 구성 문구), W19-catalog(비교 화면 문구), W20-catalog(복원 시트·메뉴 문구), W21-catalog(새 Board 만들기 시트·메뉴 문구), W22-catalog(체크포인트 시트·행·패널 문구)
# 화면 용어(0006)가 String Catalog에 있고, 화면 문구(카탈로그와 Features·App의 문자열 리터럴)에 구현 용어가 없는지 검사한다.
# 사용법: check-terms.sh [앱 소스 루트]   (기본값: 저장소의 Fianchetto/)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)/Fianchetto}"
CATALOG="$ROOT/Localizable.xcstrings"
REQUIRED=("Board 만들기" "보관된 Board" "Bishop" "Bishop 추가" "연결 대상 변경" "Board 이름 변경" "Board 보관" "보관 해제" "Wing 추가" "웹 링크 추가" "이름 변경" "URL 변경" "Wing" "웹 링크" "위로 이동" "아래로 이동" "이동" "Bishop 제거" "Wing 제거" "웹 링크 제거" "제거" "열기" "Finder에서 보기" "다시 선택…" "상태 새로고침" "권한 필요" "대상 없음" "볼륨 연결 필요" "확인 실패" "아이콘으로 보기" "목록으로 보기" "아이콘" "기본" "문서" "데이터" "이미지" "코드" "참고" "발표" "할 일" "디자인" "Bishop · 폴더" "이력" "항목" "이력 보기" "날짜로 찾기" "현재 구성" "이 시점의 기록 없음" "이 기록을 읽을 수 없습니다" "기록을 불러오지 못했습니다" "오늘 · %@" "어제 · %@" "#%lld · %@" "#%lld에서 복원" "아이콘 변경" "과거 구성에서 만듦" "가져오기" "과거 구성 · 읽기 전용" "현재로 돌아가기" "현재 구성으로 돌아가기" "#%lld · %@ 기록" "과거 구성, 읽기 전용, #%lld, %@ 기록" "고른 항목" "당시 경로" "현재 위치" "당시와 다른 위치" "당시 URL" "구성 비교" "현재와 비교" "이 기록과 비교" "비교 닫기" "순서 변경 표시" "바뀐 항목만 보기" "변화 %lld개" "Board 이름" "같은 구성입니다" "변화 없음" "순서 변경 %lld개 숨김" "표시할 변화 없음" "변경 내용" "추가됨" "제거됨" "‘%@’에서 이동" "순서 변경" "대상 교체" "이전 구성" "이후 구성" "최상위" "%@ → %@" "이름" "위치" "대상" "URL" "확인" "항목을 고르세요" "이 구성으로…" "복원…" "이 구성으로 복원…" "#%lld 구성으로 복원" "복원" "현재와 같은 구성입니다" "구성 복원" "새 Board 만들기…" "이 구성으로 새 Board 만들기…" "#%lld 구성으로 새 Board 만들기" "%@ 사본" "체크포인트 저장…" "체크포인트 저장" "진행 메모" "다음 할 일" "체크포인트 접기" "체크포인트 펴기" "체크포인트 · #%lld · %@")
# 대소문자를 구분하는 금지어와 구분하지 않는 금지어.
FORBIDDEN_EXACT=("DB" "JSON")
# "그룹"은 0017에서 Wing으로 바꾼 옛 화면 용어다. 다시 들어오지 않게 막는다.
FORBIDDEN_ANYCASE=("bookmark" "북마크" "파일 삭제" "그룹")

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
