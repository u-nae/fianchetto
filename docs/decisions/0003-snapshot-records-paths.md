# 0003 revision 스냅샷은 기록 당시 경로와 대상 정보를 함께 저장한다

- 상태: 확정 (기준 문서 간 공백 해소, 에이전트 위임)
- 날짜: 2026-10-01

## 맥락
TECH_STACK의 ResourceReference는 "최초 경로"만 가진다. PRD 불변식 7과 §6-D는 과거 구성이 기록 당시
경로를 보여 주고, 현재 해석된 위치와 다르면 둘을 구분해 표시하라고 요구한다. 북마크 갱신은 구성 이력을
바꾸지 않아야 한다(불변식 8).

## 결정
- revision 스냅샷의 파일·폴더 Node는 `referenceID` 와 함께 기록 당시 경로(`recordedPath`)와 대상 종류
  (파일/폴더)를 값으로 저장한다.
- ResourceReference는 최초 경로와 북마크 데이터, 마지막으로 해석된 경로를 운영 정보로 가진다.
  북마크 갱신은 ResourceReference만 바꾸고 revision 스냅샷은 바꾸지 않는다.
- 과거 구성 화면은 `recordedPath` 와 현재 해석 경로가 다를 때 둘을 함께 표시한다.

## 대안
- ResourceReference의 최초 경로만 사용: 같은 참조가 여러 revision에 걸쳐 쓰일 때 각 시점의 표시 경로를
  보존하지 못한다(대상 교체는 새 참조이지만 이동된 대상은 같은 참조다).

## 영향
- TECH_STACK "주요 개념"과 "데이터와 구성 이력" 설명을 갱신했다.
- 스냅샷 JSON schema version 1에 `recordedPath` 를 포함한다.
