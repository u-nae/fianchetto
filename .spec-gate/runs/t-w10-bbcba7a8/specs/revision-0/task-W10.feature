@task-W10
Feature: W10 Board 이름 변경·보관·보관 해제
  Board 이름 변경은 구성 변경이라 revision 하나를 남긴다(W05 renameProject).
  보관과 보관 해제는 Board 목록 관리 정보(보관 시각)만 바꾸고 revision을 만들지 않는다(PRD §6-C, 0005).
  보관된 Board는 읽기 전용이다: 구성 편집과 체크포인트 저장을 막고, 조회·내보내기·새 Board 만들기는 허용한다(Q-W10-1).
  Board를 영구 삭제하는 동작은 없다(PRD §4 첫 버전 제외).
  시나리오는 임시 디렉토리의 실제 저장소와 주입된 시계를 쓴다.

  # ── 이름 변경 ───────────────────────────────────────────

  @A04
  Scenario: Board 이름을 바꾸면 revision이 남고 과거 revision은 옛 이름을 가진다
    Given Board "서비스 A"가 선택돼 있다
    When "Board 이름 변경"에서 이름 "  서비스 B "를 확정한다
    Then 원인 renameProject인 revision이 하나 늘고 목록과 현재 구성의 이름은 "서비스 B"다
    And 직전 revision의 프로젝트 이름은 "서비스 A"다
    And 같은 Board가 계속 선택돼 있다

  @A04
  Scenario Outline: 같은 이름으로 확정하거나 취소하면 아무것도 기록하지 않는다
    Given Board "서비스 A"가 선택돼 있다
    When "Board 이름 변경"에서 <동작>
    Then revision 수는 그대로이고 이름은 "서비스 A"다

    Examples:
      | 동작                         |
      | 이름 " 서비스 A "를 확정한다   |
      | 이름 "서비스 B"를 입력하고 취소한다 |

  Scenario: 빈 이름은 입력을 유지하고 이름이 필요하다고 알린다
    Given Board "서비스 A"가 선택돼 있다
    When "Board 이름 변경"에서 이름 "   "을 확정한다
    Then 입력 창은 열린 채 입력을 유지하고 이름이 필요하다는 안내를 보여 준다
    And revision 수는 그대로다

  Scenario: 이름 변경 저장이 실패하면 입력을 유지하고 저장하지 못했다고 알린다
    Given Board "서비스 A"가 선택돼 있고 다음 저장 직전에 실패하도록 설정되어 있다
    When "Board 이름 변경"에서 이름 "서비스 B"를 확정한다
    Then 입력 창은 열린 채 입력을 유지하고 저장하지 못했다는 안내를 보여 준다
    And 목록의 이름은 "서비스 A"이고 revision 수는 그대로다

  # ── 보관과 보관 해제 ────────────────────────────────────

  Scenario: Board를 보관하면 revision 없이 보관된 Board로 옮겨지고 읽기 전용이 된다
    Given Board "서비스 A"와 "서비스 B"가 있고 "서비스 A"가 선택돼 있다
    When "Board 보관"을 실행한다
    Then revision 수와 현재 revision은 그대로다
    And "서비스 A"는 "보관된 Board" 묶음에 있고 계속 선택돼 있으며 현재 구성을 볼 수 있다
    And 가운데 영역은 보관된 Board라 바꿀 수 없다는 표시를 글자로 보여 준다
    And 저장소를 다시 열어도 "서비스 A"는 보관된 상태다

  Scenario: 보관을 해제하면 revision 없이 Board 목록의 원래 순서로 돌아오고 다시 바꿀 수 있다
    Given Board "서비스 A"(T0), "서비스 B"(T1)가 있고 "서비스 A"는 보관돼 있다
    When "서비스 A"를 선택하고 "보관 해제"를 실행한다
    Then revision 수는 그대로이고 Board 목록은 "서비스 A", "서비스 B" 순서다
    And 읽기 전용 표시가 사라지고 "Board 이름 변경"이 동작한다

  Scenario Outline: 보관된 Board에서는 바꾸는 동작이 아무것도 기록하지 않고 안내한다
    Given 보관된 Board "옛 프로젝트"가 선택돼 있다
    When <동작>을 실행한다
    Then 보관된 Board는 바꿀 수 없다는 안내를 보여 주고 revision 수는 그대로다

    Examples:
      | 동작               |
      | "Board 이름 변경"  |
      | "Bishop 추가"      |
      | "연결 대상 변경"   |

  Scenario Outline: 보관과 보관 해제를 같은 상태로 다시 요청하면 아무것도 바뀌지 않는다
    Given <상태>
    When <요청>
    Then 보관 시각과 revision 수는 그대로다

    Examples:
      | 상태                                  | 요청                     |
      | Board "서비스 A"가 시각 T5에 보관돼 있다 | 다시 보관을 요청한다        |
      | Board "서비스 A"가 보관되지 않았다       | 보관 해제를 요청한다        |

  Scenario: 보관 저장이 실패하면 상태가 그대로이고 저장하지 못했다고 알린다
    Given Board "서비스 A"가 선택돼 있고 다음 저장 직전에 실패하도록 설정되어 있다
    When "Board 보관"을 실행한다
    Then 저장하지 못했다는 안내를 보여 주고 "서비스 A"는 Board 목록에 그대로 있다
    And 저장소를 다시 열어도 "서비스 A"는 보관되지 않은 상태다

  Scenario: 없는 Board는 보관할 수 없다
    When 없는 Board UUID의 보관을 요청한다
    Then 결과는 project_not_found 거부이고 저장소는 그대로다

  # ── 메뉴와 문구 ─────────────────────────────────────────

  Scenario: 선택한 Board 상태에 맞는 메뉴 명령이 있고 삭제 명령은 없다
    When 파일 메뉴를 확인한다
    Then "Board 이름 변경…", "Board 보관", "보관 해제" 명령이 있다
    And Board를 영구 삭제하는 명령은 없다
    And String Catalog에 "Board 이름 변경", "Board 보관", "보관 해제" 문구가 있다
