@task-W20
Feature: W20 과거 구성으로 복원
  과거 구성 띠(W18, DESIGN.md 16.3)의 '이 구성으로…' 메뉴에서 '복원…'을 고르면 현재 구성과의 차이를 먼저 보여 주고, 사용자가 확정하면
  Board 이름과 Node 구성을 그 revision 시점으로 바꾸는 새 revision을 만든다(PRD §6-F). 새 revision의 원인은 restored이고 출처 revision ID를
  기록한다(0005). 기존 revision과 체크포인트는 그대로 두고(불변식 4), 복원 대상과 현재 구성이 같으면 revision을 만들지 않는다(PRD §7).
  복원된 구성의 항목이 지금 접근 불가능해도 제외하지 않고 그대로 복원하며, 누락 상태와 해결 동작은 W15의 연결 상태 표시로 보인다(PRD §6-F·§6-H).
  복원은 연결 대상 원본과 Git 상태를 건드리지 않는다(A08). 보관된 Board에서는 복원할 수 없다(PRD §6-C, 0009).
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
    And 변경 목록은 다음과 같다
      | 항목      | 변화                          |
      | 문서      | 제거됨                         |
      | backend  | 연결 대상 변경 /dev/api-v2 → /dev/legacy-api |
    And Board 이름 변화는 "서비스 A → 서비스 알파"로 보인다
    And 변화 종류는 기호와 문구로 표시되고 색만으로 구분하지 않는다

  Scenario: 현재와 같은 구성이면 시트는 '현재와 같은 구성입니다'를 보이고 '복원' 버튼이 없다
    Given 순번 4의 구성이 현재 구성과 Board 이름까지 같다
    And 이력 탭에서 순번 4 revision을 골라 과거 구성을 보고 있다
    When 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고른다
    Then 시트는 "현재와 같은 구성입니다"를 보이고 '복원' 버튼이 없다
    And 시트를 닫아도 revision 수는 5 그대로다

  Scenario: 차이 확인은 저장된 구성만 쓰고 파일 시스템에 접근하지 않는다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When 과거 구성 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고른다
    Then 시트가 열리는 동안 파일 시스템 접근과 연결 상태 확인은 한 번도 일어나지 않는다

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

  Scenario: 지금 접근할 수 없는 항목이 있어도 제외하지 않고 복원하며 상태와 해결 동작을 보인다
    Given 참조 R1의 대상 /dev/legacy-api는 지금 없다
    And 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '복원'을 누른다
    Then 현재 구성에 "backend"가 참조 R1로 남아 있다
    And "backend"에 연결 상태 "대상 없음"이 기호와 문구로 보이고 '다시 선택…'과 '상태 새로고침'을 쓸 수 있다
    And 상태 확인은 revision을 만들지 않아 revision 수는 6이다

  Scenario: 현재 구성 저장이 실패하면 이전 현재 구성이 유지되고 저장 실패를 알린다
    Given 저장소가 다음 저장에서 실패하도록 주입되어 있다
    And 순번 2 revision의 "#2 구성으로 복원" 시트가 열려 있다
    When '복원'을 누른다
    Then revision 수는 5이고 현재 revision은 순번 5 그대로다
    And 저장 실패 알림이 보이고 가운데 영역은 순번 2 과거 구성 보기가 이어진다

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

  Scenario: 복원으로 생긴 revision도 다시 복원 대상이 된다
    Given 순번 2로 복원해 순번 6이 현재다
    When 이력 탭에서 순번 5 revision을 골라 '복원…'을 고르고 '복원'을 누른다
    Then revision 수는 7이고 순번 7의 원인은 restored이며 출처 revision은 순번 5다
    And 순번 7의 구성과 Board 이름은 순번 5와 같다

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

  Scenario: 현재 구성을 읽을 수 없으면 복원하지 않고 오류를 알린다
    Given "서비스 A"의 현재 revision 스냅샷이 손상되어 읽을 수 없다
    When 서비스에 순번 2 revision으로의 복원을 요청한다
    Then 결과는 현재 구성 읽기 오류이고 빈 구성으로 대신하지 않으며 revision 수는 5 그대로다
