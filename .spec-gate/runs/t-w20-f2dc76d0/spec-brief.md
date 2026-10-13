# 명세 브리프 — W20 과거 구성으로 복원

## 1. 작업 항목

| task_id | title | route | acceptance_refs |
| --- | --- | --- | --- |
| W20 | 과거 구성으로 복원 | BOTH | A08 |

기준 문서:
- docs/PRD.md (9194c2af1e20)
- docs/TECH_STACK.md (3b623d55c2cc)

run_id: t-w20-f2dc76d0

## 2. 승인된 명세

### .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature

```gherkin
@task-W20
Feature: W20 과거 구성으로 복원
  과거 구성 띠(W18, DESIGN.md 16.3)의 '이 구성으로…' 메뉴에서 '복원…'을 고르면 복원 전용 확인 시트가 현재 구성과의 차이를 먼저 보여 주고(Q-W20-1=A),
  사용자가 확정하면 Board 이름과 Node 구성을 그 revision 시점으로 바꾸는 새 revision을 만든다(PRD §6-F). 새 revision의 원인은 restored이고 출처 revision ID를
  기록한다(0005). 기존 revision과 체크포인트는 그대로 두고(불변식 4), 복원 대상과 현재 구성이 같으면 revision을 만들지 않는다(PRD §7).
  복원된 구성의 항목이 지금 접근 불가능해도 제외하지 않고 그대로 복원한다. 누락 상태와 해결 동작은 W15의 연결 상태 표시로 보이며, 상태 확인은
  W15 규칙대로 선택·열기·명시적 새로고침 때만 일어난다(PRD §6-F·§6-H·§8). 복원은 연결 대상 원본과 Git 상태를 건드리지 않는다(A08).
  보관된 Board에서는 복원할 수 없다(PRD §6-C, 0009). 메뉴 막대에서는 파일 메뉴 '이 구성으로 복원…'으로 같은 시트를 연다(Q-W20-2=A, 0018).
  과거와 현재, 변화 종류를 색만으로 구분하지 않는다.

  Background:
    Given Board "서비스 A"의 revision이 다음과 같다
      | 순번 | 원인            | 구성                                                                                   |
      | 1   | created        | Board 이름 "서비스 알파", 비어 있음                                                            |
      | 2   | addLinkedItems | 최상위에 Bishop 폴더 "backend"(참조 R1, 당시 경로 /dev/legacy-api)와 Wing "개발"                   |
      | 3   | replaceTarget  | "backend"가 참조 R2(당시 경로 /dev/api-v2)를 쓴다                                             |
      | 4   | addGroup       | Wing "문서"를 더했다                                                                      |
      | 5   | renameProject  | Board 이름이 "서비스 A"가 되었다                                                              |
    And 현재 revision은 순번 5이고 revision 수는 5다
    And 순번 3에 체크포인트 "1차 정리"가 붙어 있다
    And 참조 레코드는 R1, R2 둘이다

  # ── 진입 ─────────────────────────────────────────────

  @A08
  Scenario: 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고르면 차이 확인 시트가 열린다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고른다
    Then "#2 구성으로 복원" 시트가 열린다
    And 시트의 이전 대상은 "현재 구성", 이후 대상은 "#2 · " 기록 시각이다
    And 시트에는 '취소'와 '복원' 버튼이 있다
    And revision 수는 5 그대로다

  Scenario: 현재 구성을 볼 때는 과거 구성 띠가 없으므로 '이 구성으로…' 메뉴도 없다
    Given 현재 구성을 보고 있다
    Then 가운데 영역에 과거 구성 띠와 '이 구성으로…' 메뉴가 없다

  Scenario: 보관된 Board의 과거 구성 띠에서는 '복원…'만 꺼지고 '현재와 비교'는 켜진다
    Given "서비스 A"가 보관되어 있고 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    Then 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'은 꺼져 있다
    And '현재와 비교'는 켜져 있다

  Scenario Outline: 파일 메뉴 '이 구성으로 복원…'은 과거 구성을 볼 때만 켜지고 띠의 '복원…'과 같은 시트를 연다
    Given <상태>
    Then 파일 메뉴 '이 구성으로 복원…'은 <켜짐>이다

    Examples:
      | 상태                                 | 켜짐 |
      | 현재 구성을 보고 있다                     | 꺼짐 |
      | 순번 2 과거 구성을 보고 있다                | 켜짐 |
      | 순번 2와 현재 구성을 비교하고 있다            | 꺼짐 |
      | 보관된 Board의 순번 2 과거 구성을 보고 있다    | 꺼짐 |

  Scenario: 파일 메뉴로 열어도 띠에서 연 것과 같은 시트다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When 파일 메뉴 '이 구성으로 복원…'을 실행한다
    Then "#2 구성으로 복원" 시트가 열린다

  # ── 차이 확인 ─────────────────────────────────────────

  @A08
  Scenario: 확인 시트는 현재 구성에서 복원 결과로의 변화를 요약과 변경 목록으로 보인다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고른다
    Then 시트의 요약은 "변화 2개 · Board 이름 변경"이다
    And 변경 목록은 DESIGN.md 19.3 변화 문구를 쓰고 값은 '이전 → 이후'(현재 → 복원 결과) 순서다
      | 항목      | 변화                                    |
      | 문서      | 제거됨                                   |
      | backend  | 대상 교체 /dev/api-v2 → /dev/legacy-api     |
    And Board 이름 변화는 "서비스 A → 서비스 알파"로 보인다
    And 변화 종류는 기호와 문구로 표시되고 색만으로 구분하지 않는다

  Scenario: 현재와 같은 구성이면 시트는 '현재와 같은 구성입니다'를 보이고 '복원' 버튼이 없다
    Given 이력 탭에서 순번 5 revision을 골라 과거 구성을 보고 있다
    When 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고른다
    Then 시트는 "현재와 같은 구성입니다"를 보이고 '복원' 버튼이 없으며 '닫기'만 있다
    And 시트를 닫아도 revision 수는 5 그대로다

  Scenario: 차이 확인은 저장된 구성만 쓰고 파일 시스템에 접근하지 않는다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고른다
    Then 시트가 열리는 동안 파일 시스템 접근과 연결 상태 확인은 한 번도 일어나지 않는다

  Scenario: 시트의 키보드와 접근성: Esc는 '취소', Return은 '복원', 요약과 변경 목록은 접근성 요소로 읽힌다
    Given 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    Then '복원'이 기본 버튼이고 Return 키는 '복원'과 같다
    And Esc 키는 '취소'와 같고, 비교 띠가 뒤에 있어도 시트의 Esc가 먼저다(DESIGN.md 19.6)
    And VoiceOver는 시트 제목, 요약, 변경 목록의 각 행(항목과 변화 문구)을 차례로 읽는다

  Scenario: '취소'하면 revision이 생기지 않고 과거 구성 보기가 이어진다
    Given 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '취소'를 누른다
    Then 시트가 닫히고 가운데 영역은 순번 2 구성이며 과거 구성 띠가 보인다
    And revision 수는 5 그대로다

  # ── 확정 ─────────────────────────────────────────────

  @A08
  Scenario: '복원'을 확정하면 Board 이름과 구성이 그 revision과 같은 새 revision이 현재가 된다
    Given 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '복원'을 누른다
    Then revision 수는 6이고 현재 revision은 순번 6이다
    And 순번 6의 원인은 restored이고 출처 revision은 순번 2다
    And 순번 6의 Board 이름은 "서비스 알파"이고 구성은 순번 2 구성과 같다
    And 가운데 영역은 현재 구성이고 과거 구성 띠가 없으며 이력 탭의 "현재 구성" 행이 골라져 있다
    And 이력 탭의 순번 6 행 원인 문구는 "#2에서 복원"이다

  @A08
  Scenario: 복원은 기존 revision과 체크포인트를 바꾸지 않는다
    Given 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '복원'을 누른다
    Then 순번 1부터 5까지의 revision은 원인·구성·기록 시각이 그대로다
    And 체크포인트 "1차 정리"는 순번 3에 그대로 붙어 있고 체크포인트 수는 1이다

  Scenario: 복원된 항목은 그 revision의 reference를 그대로 쓰고 새 reference를 만들지 않는다
    Given 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '복원'을 누른다
    Then 현재 구성의 "backend"는 참조 R1을 쓴다
    And 참조 레코드는 R1, R2 그대로 둘이다
    And "backend"의 Node UUID는 순번 2와 같다

  Scenario: 지금 접근할 수 없는 항목도 제외하지 않고 복원하며, 상태는 W15 규칙대로 고를 때 확인해 해결 동작과 함께 보인다
    Given 참조 R1의 대상 /dev/legacy-api는 지금 없다
    And 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '복원'을 누른다
    Then 현재 구성에 "backend"가 참조 R1로 남아 있다
    And 복원 직후에는 접근 정보 해석이 한 번도 일어나지 않는다
    When 현재 구성에서 "backend"를 고른다
    Then "backend"에 연결 상태 "대상 없음"이 기호와 문구로 보이고 '다시 선택…'과 '상태 새로고침'을 쓸 수 있다
    And 상태 확인은 revision을 만들지 않아 revision 수는 6이다

  Scenario: 현재 구성 저장이 실패하면 이전 현재 구성이 유지되고 시트는 닫히며 저장 실패를 알린다
    Given 저장소가 다음 저장에서 실패하도록 주입되어 있다
    And 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '복원'을 누른다
    Then revision 수는 5이고 현재 revision은 순번 5 그대로다
    And 시트는 닫히고 저장 실패 알림이 보이며 가운데 영역은 순번 2 과거 구성 보기가 이어진다
    And 다시 시도하려면 '복원…'을 다시 고른다

  Scenario: 복원은 연결 대상 원본 파일·폴더를 읽거나 바꾸지 않는다
    Given 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '복원'을 누른다
    Then 복원 과정에서 파일 시스템 쓰기와 연결 대상 열기는 한 번도 일어나지 않는다
    And /dev/legacy-api와 /dev/api-v2의 내용은 그대로다

  Scenario: Board 이름만 다른 revision으로 복원하면 이름을 되돌리는 revision이 생긴다
    Given 이력 탭에서 순번 4 revision을 골라 과거 구성을 보고 있고 순번 4와 현재 구성은 Board 이름만 다르다
    When 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고르고 '복원'을 누른다
    Then revision 수는 6이고 순번 6의 Board 이름은 "서비스 알파"다
    And 순번 6의 Node 구성은 순번 5와 같다

  Scenario: 복원으로 생긴 revision도 다시 복원 대상이 되고 출처는 그 revision이다
    Given 순번 2로 복원해 순번 6이 현재다
    And Wing "임시"를 더해 순번 7이 현재다
    When 이력 탭에서 순번 6 revision을 골라 '복원…'을 고르고 '복원'을 누른다
    Then revision 수는 8이고 순번 8의 원인은 restored이며 출처 revision은 순번 6이다
    And 순번 8의 구성과 Board 이름은 순번 6(= 순번 2)과 같고 Wing "임시"는 없다

  # ── 서비스 경계 ─────────────────────────────────────────

  Scenario Outline: 서비스는 복원 요청을 결정표 restore_request_outcome으로 판정하고 첫 번째로 맞는 규칙의 outcome을 돌려준다
    Given board_state가 <board_state>, target_revision이 <target_revision>, current_snapshot이 <current_snapshot>, target_vs_current가 <target_vs_current>다
    When 서비스에 복원을 요청한다
    Then outcome은 <outcome>이고 revision은 outcome이 restored일 때만 하나 늘어난다

    Examples:
      | board_state | target_revision | current_snapshot | target_vs_current | outcome                      |
      | archived    | found           | readable         | different         | rejected_archived            |
      | active      | not_found       | readable         | different         | rejected_revision_not_found  |
      | active      | other_board     | unreadable       | same              | rejected_revision_not_found  |
      | active      | unreadable      | readable         | different         | error_target_unreadable      |
      | active      | unreadable      | unreadable       | same              | error_target_unreadable      |
      | active      | found           | unreadable       | different         | error_current_unreadable     |
      | active      | found           | readable         | same              | unchanged                    |
      | active      | found           | readable         | different         | restored                     |

  Scenario: 보관된 Board에 복원을 요청하면 거부되고 revision이 생기지 않는다
    Given "서비스 A"가 보관되어 있다
    When 서비스에 순번 2 revision으로의 복원을 요청한다
    Then 결과는 거부(archived)이고 revision 수는 5 그대로다

  Scenario: 없는 revision이나 다른 Board의 revision을 복원 대상으로 주면 거부된다
    Given Board "서비스 B"의 revision X가 있다
    When 서비스에 "서비스 A"의 복원 대상으로 revision X 또는 없는 ID를 준다
    Then 결과는 거부(revision_not_found)이고 "서비스 A"의 revision 수는 5 그대로다

  Scenario: 대상 revision의 스냅샷을 읽을 수 없으면 복원하지 않고 오류를 알린다
    Given 순번 2 revision의 구성 JSON이 손상되어 디코딩할 수 없다
    When 서비스에 순번 2 revision으로의 복원을 요청한다
    Then 결과는 대상 구성 읽기 오류이고 빈 구성으로 대신하지 않으며 revision 수는 5 그대로다

  Scenario: 현재 구성을 읽을 수 없으면 복원하지 않고 오류를 알린다
    Given "서비스 A"의 현재 revision 스냅샷이 손상되어 읽을 수 없다
    When 서비스에 순번 2 revision으로의 복원을 요청한다
    Then 결과는 현재 구성 읽기 오류이고 빈 구성으로 대신하지 않으며 revision 수는 5 그대로다
```

### .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/W20.decision.yaml

| rule_id | board_state | target_revision | current_snapshot | target_vs_current | outcome |
| --- | --- | --- | --- | --- | --- |
| R1 | archived | (blank) | (blank) | (blank) | rejected_archived |
| R2 | (blank) | [not_found, other_board] | (blank) | (blank) | rejected_revision_not_found |
| R3 | (blank) | unreadable | (blank) | (blank) | error_target_unreadable |
| R4 | (blank) | (blank) | unreadable | (blank) | error_current_unreadable |
| R5 | (blank) | (blank) | (blank) | same | unchanged |
| R6 | (blank) | (blank) | (blank) | different | restored |

셀 맵

| board_state | target_revision | current_snapshot | target_vs_current | rule_id |
| --- | --- | --- | --- | --- |
| active | found | readable | same | R5 |
| active | found | readable | different | R6 |
| active | found | unreadable | same | R4 |
| active | found | unreadable | different | R4 |
| active | not_found | readable | same | R2 |
| active | not_found | readable | different | R2 |
| active | not_found | unreadable | same | R2 |
| active | not_found | unreadable | different | R2 |
| active | other_board | readable | same | R2 |
| active | other_board | readable | different | R2 |
| active | other_board | unreadable | same | R2 |
| active | other_board | unreadable | different | R2 |
| active | unreadable | readable | same | R3 |
| active | unreadable | readable | different | R3 |
| active | unreadable | unreadable | same | R3 |
| active | unreadable | unreadable | different | R3 |
| archived | found | readable | same | R1 |
| archived | found | readable | different | R1 |
| archived | found | unreadable | same | R1 |
| archived | found | unreadable | different | R1 |
| archived | not_found | readable | same | R1 |
| archived | not_found | readable | different | R1 |
| archived | not_found | unreadable | same | R1 |
| archived | not_found | unreadable | different | R1 |
| archived | other_board | readable | same | R1 |
| archived | other_board | readable | different | R1 |
| archived | other_board | unreadable | same | R1 |
| archived | other_board | unreadable | different | R1 |
| archived | unreadable | readable | same | R1 |
| archived | unreadable | readable | different | R1 |
| archived | unreadable | unreadable | same | R1 |
| archived | unreadable | unreadable | different | R1 |

### .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/W20.decision.vectors.yaml

벡터 파일 (§4에 반영)

## 3. Test obligations

| obligation_id | kind | description | acceptance_refs | source |
| --- | --- | --- | --- | --- |
| W20-restore-menu-opens-sheet | scenario | 과거 구성 띠 '이 구성으로…' › '복원…'이 "#n 구성으로 복원" 시트를 열고(이전=현재, 이후=#n) revision을 만들지 않는다 | A08 | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고르면 차이 확인 시트가 열린다 |
| W20-no-menu-on-current | scenario | 현재 구성을 볼 때는 과거 구성 띠와 '이 구성으로…' 메뉴가 없다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#현재 구성을 볼 때는 과거 구성 띠가 없으므로 '이 구성으로…' 메뉴도 없다 |
| W20-archived-disables-restore-only | scenario | 보관된 Board의 띠에서 '복원…'만 꺼지고 '현재와 비교'는 켜진다(0009) |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#보관된 Board의 과거 구성 띠에서는 '복원…'만 꺼지고 '현재와 비교'는 켜진다 |
| W20-file-menu-enablement | scenario | 파일 메뉴 '이 구성으로 복원…'의 켜짐 조건 네 가지(현재/과거/비교 중/보관) |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#파일 메뉴 '이 구성으로 복원…'은 과거 구성을 볼 때만 켜지고 띠의 '복원…'과 같은 시트를 연다 |
| W20-file-menu-same-sheet | scenario | 파일 메뉴로 열어도 띠에서 연 것과 같은 시트가 열린다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#파일 메뉴로 열어도 띠에서 연 것과 같은 시트다 |
| W20-sheet-shows-diff | scenario | 시트의 요약(0027 규칙)과 변경 목록(19.3 변화 문구), Board 이름 변화, 기호+문구 표시 | A08 | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#확인 시트는 현재 구성에서 복원 결과로의 변화를 요약과 변경 목록으로 보인다 |
| W20-sheet-identical-no-button | scenario | 현재와 같은 구성이면 '현재와 같은 구성입니다'를 보이고 '복원' 버튼이 없으며 revision이 생기지 않는다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#현재와 같은 구성이면 시트는 '현재와 같은 구성입니다'를 보이고 '복원' 버튼이 없다 |
| W20-sheet-no-file-access | scenario | 차이 확인은 저장된 구성만 쓰고 파일 시스템 접근·연결 상태 확인을 하지 않는다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#차이 확인은 저장된 구성만 쓰고 파일 시스템에 접근하지 않는다 |
| W20-sheet-keyboard-accessibility | scenario | 시트의 기본 버튼은 복원(Return), Esc는 취소이며 시트의 Esc가 비교 띠보다 먼저이고 제목·요약·변경 목록 행이 VoiceOver로 읽힌다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#시트의 키보드와 접근성: Esc는 '취소', Return은 '복원', 요약과 변경 목록은 접근성 요소로 읽힌다 |
| W20-cancel-keeps-past-view | scenario | '취소'는 revision을 만들지 않고 과거 구성 보기를 이어 간다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#'취소'하면 revision이 생기지 않고 과거 구성 보기가 이어진다 |
| W20-confirm-creates-restored-revision | scenario | 확정 시 cause restored(from | A08 | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#'복원'을 확정하면 Board 이름과 구성이 그 revision과 같은 새 revision이 현재가 된다 |
| W20-history-and-checkpoints-preserved | scenario | 기존 revision 1~5의 원인·구성·시각과 체크포인트가 그대로다(불변식 4) | A08 | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#복원은 기존 revision과 체크포인트를 바꾸지 않는다 |
| W20-reuses-recorded-references | scenario | 복원된 항목은 기록된 reference(R1)를 쓰고 새 reference를 만들지 않으며 Node UUID를 유지한다(불변식 1·3·7) |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#복원된 항목은 그 revision의 reference를 그대로 쓰고 새 reference를 만들지 않는다 |
| W20-restores-unreachable-items | scenario | 접근 불가 항목도 제외하지 않고 복원하고, 복원 직후에는 접근 정보 해석이 없으며, 항목을 고르면 "대상 없음"과 해결 동작이 보이고 상태 확인은 revision을 만들지 않는다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#지금 접근할 수 없는 항목도 제외하지 않고 복원하며, 상태는 W15 규칙대로 고를 때 확인해 해결 동작과 함께 보인다 |
| W20-save-failure-keeps-current | scenario | 저장 실패 주입 시 revision 수·현재 revision이 그대로이고 시트가 닫히며 알림이 보이고 과거 구성 보기가 이어진다(PRD §7) |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#현재 구성 저장이 실패하면 이전 현재 구성이 유지되고 시트는 닫히며 저장 실패를 알린다 |
| W20-no-disk-side-effects | scenario | 복원은 파일 시스템 쓰기·연결 대상 열기를 하지 않고 원본 내용이 그대로다(A08) | A08 | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#복원은 연결 대상 원본 파일·폴더를 읽거나 바꾸지 않는다 |
| W20-name-only-restore | scenario | Board 이름만 다른 revision으로 복원하면 이름을 되돌리는 revision이 생기고 Node 구성은 그대로다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#Board 이름만 다른 revision으로 복원하면 이름을 되돌리는 revision이 생긴다 |
| W20-restore-chain | scenario | 복원 revision(순번 6)을 대상으로 다시 복원하면 출처가 순번 6이고 구성이 순번 6과 같다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#복원으로 생긴 revision도 다시 복원 대상이 되고 출처는 그 revision이다 |
| W20-service-outcome-table | scenario | 서비스의 복원 판정은 결정표 restore_request_outcome(FIRST)과 같고 outcome이 restored일 때만 revision이 늘어난다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#서비스는 복원 요청을 결정표 restore_request_outcome으로 판정하고 첫 번째로 맞는 규칙의 outcome을 돌려준다 |
| W20-service-rejects-archived | scenario | 서비스는 보관된 Board의 복원 요청을 archived로 거부하고 revision을 만들지 않는다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#보관된 Board에 복원을 요청하면 거부되고 revision이 생기지 않는다 |
| W20-service-rejects-foreign-revision | scenario | 없는 revision이나 다른 Board의 revision은 revision_not_found로 거부된다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#없는 revision이나 다른 Board의 revision을 복원 대상으로 주면 거부된다 |
| W20-service-target-unreadable | scenario | 대상 revision의 구성 JSON을 디코딩할 수 없으면 대상 구성 읽기 오류이고 빈 구성으로 대신하지 않는다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#대상 revision의 스냅샷을 읽을 수 없으면 복원하지 않고 오류를 알린다 |
| W20-service-current-unreadable | scenario | 현재 스냅샷을 읽을 수 없으면 오류이고 빈 구성으로 대신하지 않는다 |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/task-W20.feature#현재 구성을 읽을 수 없으면 복원하지 않고 오류를 알린다 |
| W20-restore_request_outcome-R1 | decision-rule | 보관된 Board는 대상·현재 상태와 무관하게 rejected_archived |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/W20.decision.yaml#R1 |
| W20-restore_request_outcome-R2 | decision-rule | 대상 revision이 없거나 다른 Board면 rejected_revision_not_found |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/W20.decision.yaml#R2 |
| W20-restore_request_outcome-R3 | decision-rule | 대상 revision의 스냅샷을 읽거나 디코딩할 수 없으면 error_target_unreadable |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/W20.decision.yaml#R3 |
| W20-restore_request_outcome-R4 | decision-rule | 현재 스냅샷을 읽을 수 없으면 error_current_unreadable |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/W20.decision.yaml#R4 |
| W20-restore_request_outcome-R5 | decision-rule | 대상이 현재와 같으면 unchanged(revision 없음) |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/W20.decision.yaml#R5 |
| W20-restore_request_outcome-R6 | decision-rule | 대상이 현재와 다르면 restored (cause는 restored, 출처는 대상 revision) |  | .spec-gate/runs/t-w20-f2dc76d0/specs/revision-1/W20.decision.yaml#R6 |

## 4. 결정 벡터

### restore_request_outcome

| rule_id | obligation_id | inputs | expected |
| --- | --- | --- | --- |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=found, current_snapshot=readable, target_vs_current=same | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=found, current_snapshot=readable, target_vs_current=different | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=found, current_snapshot=unreadable, target_vs_current=same | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=found, current_snapshot=unreadable, target_vs_current=different | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=not_found, current_snapshot=readable, target_vs_current=same | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=not_found, current_snapshot=readable, target_vs_current=different | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=not_found, current_snapshot=unreadable, target_vs_current=same | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=not_found, current_snapshot=unreadable, target_vs_current=different | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=other_board, current_snapshot=readable, target_vs_current=same | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=other_board, current_snapshot=readable, target_vs_current=different | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=other_board, current_snapshot=unreadable, target_vs_current=same | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=other_board, current_snapshot=unreadable, target_vs_current=different | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=unreadable, current_snapshot=readable, target_vs_current=same | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=unreadable, current_snapshot=readable, target_vs_current=different | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=unreadable, current_snapshot=unreadable, target_vs_current=same | outcome=rejected_archived |
| R1 | W20-restore_request_outcome-R1 | board_state=archived, target_revision=unreadable, current_snapshot=unreadable, target_vs_current=different | outcome=rejected_archived |
| R2 | W20-restore_request_outcome-R2 | board_state=active, target_revision=not_found, current_snapshot=readable, target_vs_current=same | outcome=rejected_revision_not_found |
| R2 | W20-restore_request_outcome-R2 | board_state=active, target_revision=not_found, current_snapshot=readable, target_vs_current=different | outcome=rejected_revision_not_found |
| R2 | W20-restore_request_outcome-R2 | board_state=active, target_revision=not_found, current_snapshot=unreadable, target_vs_current=same | outcome=rejected_revision_not_found |
| R2 | W20-restore_request_outcome-R2 | board_state=active, target_revision=not_found, current_snapshot=unreadable, target_vs_current=different | outcome=rejected_revision_not_found |
| R2 | W20-restore_request_outcome-R2 | board_state=active, target_revision=other_board, current_snapshot=readable, target_vs_current=same | outcome=rejected_revision_not_found |
| R2 | W20-restore_request_outcome-R2 | board_state=active, target_revision=other_board, current_snapshot=readable, target_vs_current=different | outcome=rejected_revision_not_found |
| R2 | W20-restore_request_outcome-R2 | board_state=active, target_revision=other_board, current_snapshot=unreadable, target_vs_current=same | outcome=rejected_revision_not_found |
| R2 | W20-restore_request_outcome-R2 | board_state=active, target_revision=other_board, current_snapshot=unreadable, target_vs_current=different | outcome=rejected_revision_not_found |
| R3 | W20-restore_request_outcome-R3 | board_state=active, target_revision=unreadable, current_snapshot=readable, target_vs_current=same | outcome=error_target_unreadable |
| R3 | W20-restore_request_outcome-R3 | board_state=active, target_revision=unreadable, current_snapshot=readable, target_vs_current=different | outcome=error_target_unreadable |
| R3 | W20-restore_request_outcome-R3 | board_state=active, target_revision=unreadable, current_snapshot=unreadable, target_vs_current=same | outcome=error_target_unreadable |
| R3 | W20-restore_request_outcome-R3 | board_state=active, target_revision=unreadable, current_snapshot=unreadable, target_vs_current=different | outcome=error_target_unreadable |
| R4 | W20-restore_request_outcome-R4 | board_state=active, target_revision=found, current_snapshot=unreadable, target_vs_current=same | outcome=error_current_unreadable |
| R4 | W20-restore_request_outcome-R4 | board_state=active, target_revision=found, current_snapshot=unreadable, target_vs_current=different | outcome=error_current_unreadable |
| R5 | W20-restore_request_outcome-R5 | board_state=active, target_revision=found, current_snapshot=readable, target_vs_current=same | outcome=unchanged |
| R6 | W20-restore_request_outcome-R6 | board_state=active, target_revision=found, current_snapshot=readable, target_vs_current=different | outcome=restored |

## 5. 결정

| question_id | question | answer | recommended_default | followed_recommendation |
| --- | --- | --- | --- | --- |
| Q-W20-1 | '복원…'을 고른 뒤 현재와의 차이를 어떤 화면에서 확인하고 확정할까요? | A | A | true |
| Q-W20-2 | '이 구성으로 복원…'을 메뉴 막대 어디에 둘까요? | A | A | true |

결정 기록:
- docs/decisions/0034-restore-confirmation-sheet.md
- docs/decisions/0035-restore-in-file-menu.md

## 6. Non-blocking notes

- F-W20-11 (W20): 작성자가 적용했다고 주장한 일곱 건을 산출물로 확인했다. F-W20-1: 결정표 입력 영역에 target_revision=unreadable이 들어가 R3이 4칸을 이기고 check-decision 결과 빈 칸이 없다. R2(not_found·other_board)와 R3(unreadable)은 값이 달라 겹치지 않고, 서비스 시나리오와 outline 예시가 "빈 구성으로 대신하지 않는다"를 고정한다. 해소. F-W20-2: 복원 직후 해석 없음을 단언한 뒤 항목 선택을 When으로 두어 확인 시점이 W15 규칙과 같아졌고 헤더·가정 3도 맞췄다. 해소. F-W20-3: 순번 5(현재 revision) 행을 대상으로 바꿔 Background와 모순이 없다. 해소. F-W20-4: 19.3 어휘 '대상 교체'와 값 순서를 적었다. 해소. F-W20-5: 순번 6을 실제로 고르는 단계가 있어 제목이 검증된다. 해소. F-W20-6: 시트 상태와 재시도 경로를 정했다. 해소. F-W20-7: 키보드·접근성 시나리오를 더했다. 해소. F-W20-9는 가정 9와 표 주석으로, F-W20-10은 두 답(A·A)으로 닫혔고 revision-1의 '진입'· '차이 확인' 절은 답 A·A(복원 전용 시트, 파일 메뉴)와 일치한다. F-W20-8(순번 2 fixture가 Bishop과 Wing을 함께 더함)은 바뀌지 않았으나 원래 수정 요청이 없던 참고 사항이다. 블로킹 질문은 남아 있지 않다.
- F-W20-12 (W20): revision-1로 다시 쓰는 과정에서 obligation 설명이 잘렸다. 시나리오 본문(task-W20.feature:99-106)과 source 로케이터는 온전하므로 수용 경계는 바뀌지 않지만, handoff와 spec-brief가 이 설명을 그대로 옮기므로 TDD 담당자가 보는 obligation 목록에 의미가 끊긴 문장이 남는다.
- F-W20-13 (W20): outline 제목의 뒷부분("같은 시트를 연다")은 그 outline의 단계가 검증하지 않고 바로 다음 시나리오(:54)가 검증한다. obligation 설명은 단계와 맞으므로 TDD 방향은 바뀌지 않는다.
- F-W20-14 (W20): 한 When에 두 입력 경우를 '또는'으로 묶어 시나리오 하나가 두 동작을 말한다. 결정표 R2의 per-rule obligation이 not_found와 other_board를 각각 벡터로 분리하므로 테스트 경계는 손상되지 않는다. revision-0부터 같은 형태였고 pass 1에서도 요청하지 않았다.
- F-W20-15 (W20): '닫기'만 있는 변형 시트의 Esc·Return 동작은 적혀 있지 않다. 버튼이 하나뿐이라 Esc와 Return이 모두 '닫기'인 macOS 기본 관례 외의 해석이 없고, revision을 만들지 않는 조회 경로라 수용 경계와 무관하다.

## 7. 검증 계약

모든 테스트의 이름 또는 태그에 그 테스트가 증명하는 obligation_id를 포함한다. /spec-cycle:verify 가 이 문자열을 찾는다.
