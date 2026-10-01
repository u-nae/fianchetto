# 0005 출처(provenance)와 보관 상태를 명시 필드로 둔다

- 상태: 확정 (기준 문서 간 공백 해소, 에이전트 위임)
- 날짜: 2026-10-01

## 맥락
PRD는 복원 revision의 출처 revision ID(§6-F), 과거 구성에서 만든 새 프로젝트의 원본 프로젝트·revision
출처(§6-F), 가져오기의 원본 ID provenance(§6-I), 프로젝트 보관 상태(F01, §6-C)를 요구한다. TECH_STACK의
Project·Revision 필드 목록에는 이 정보가 없다.

## 결정
- Revision: `restoredFromRevisionID`(선택). 복원으로 생긴 revision에만 값이 있다. `cause` 는 변경 원인
  (생성, 편집 종류, 복원, 복제, 가져오기)을 열거형으로 기록한다.
- Project: `origin`(선택) — 종류(복제/가져오기), 원본 프로젝트 ID, 원본 revision ID. 가져오기의 원본 ID는
  provenance로만 보존하고 내부 관계에는 새 ID를 쓴다.
- Project: `archivedAt`(선택). 보관은 목록 관리 정보라 revision을 만들지 않는다. 보관된 프로젝트의 편집은
  서비스 계층에서 거부한다.

## 대안
- 출처를 revision 원인 문자열에만 기록: 조회·검증할 수 없는 자유 텍스트가 된다.
- 보관을 revision으로 기록: PRD §6-C가 명시적으로 배제한다.

## 영향
- TECH_STACK "주요 개념"의 Project·Revision 필드를 갱신했다.
- 내보내기 manifest는 이 필드를 포함하고, 가져오기 검증은 출처 필드의 형식만 검사한다(원본 존재 여부는 요구하지 않는다).
