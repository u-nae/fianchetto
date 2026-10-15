@task-W21
Feature: W21 과거 구성에서 새 Board 만들기
  과거 구성 띠(W18, DESIGN.md 16.3)의 '이 구성으로…' 메뉴에서 '새 Board 만들기…'를 고르면 새 Board의 이름을 받는 시트가 열리고,
  확정하면 사용자가 입력한 이름과 그 revision 구성의 복사본으로 독립적인 새 Board를 만든다(PRD §6-F).
  Board와 Node에는 새 UUID를 주고 부모 관계를 재매핑한다(순수 Domain 함수, 디스크 접근 없음). 원본 Board와 revision은 새 Board의 출처(origin)로
  기록하고(0005), 원본 이력·체크포인트는 복사하지 않는다. 새 Board의 첫 revision(순번 1)은 복사된 구성이고 원인은 duplicated다(DESIGN.md 16.2).
  연결 참조는 원본과 같은 참조 레코드를 그대로 쓰고 새 참조 레코드를 만들지 않는다(Q-W21-1=A, 사용자 확정).
  보관된 Board에서도 새 Board를 만들 수 있다(PRD §6-C, 0009). 메뉴 막대에서는 파일 메뉴 '이 구성으로 새 Board 만들기…'(0018, 0035와 같은 자리)로
  같은 시트를 연다. 만들기는 연결 대상 원본 파일·폴더를 읽거나 바꾸지 않는다. 과거와 현재, 상태를 색만으로 구분하지 않는다.

  Background:
    Given Board "서비스 A"의 revision이 다음과 같다
      | 순번 | 원인            | 구성                                                                                   |
      | 1   | created        | Board 이름 "서비스 알파", 비어 있음                                                            |
      | 2   | addLinkedItems | 최상위에 Bishop 폴더 "backend"(참조 R1, 당시 경로 /dev/legacy-api)와 Wing "개발"                   |
      | 3   | replaceTarget  | "backend"가 참조 R2(당시 경로 /dev/api-v2)를 쓴다                                             |
      | 4   | addGroup       | Wing "문서"를 더했고, "개발" 아래에 웹 링크 "명세"(https://example.com/spec)와 Bishop 파일 "notes.md"(참조 R3, 아이콘 document)가 있다 |
      | 5   | renameProject  | Board 이름이 "서비스 A"가 되었다                                                              |
    And 현재 revision은 순번 5이고 revision 수는 5다
    And 순번 3에 체크포인트 "1차 정리"가 붙어 있다
    And 참조 레코드는 R1, R2, R3 셋이다
    And Board 목록에는 "서비스 A" 하나가 있다

  # ── 진입 ─────────────────────────────────────────────

  Scenario: 과거 구성 띠의 '이 구성으로…' 메뉴에서 '새 Board 만들기…'를 고르면 이름을 받는 시트가 열린다
    Given 이력 탭에서 순번 4 revision을 골라 과거 구성을 보고 있다
    When 과거 구성 띠의 '이 구성으로…' 메뉴에서 '새 Board 만들기…'를 고른다
    Then "#4 구성으로 새 Board 만들기" 시트가 열린다
    And 시트의 부제는 "서비스 알파 · #4 · " 기록 시각이다
    And 'Board 이름' 필드의 값은 "서비스 알파 사본"이고 전체가 선택되어 있다
    And 시트에는 안내 "새 Board는 이 구성으로 시작하고 이력은 새로 쌓입니다. 원래 Board는 바뀌지 않습니다."가 있다
    And 시트에는 '취소'와 '만들기' 버튼이 있다
    And Board 목록은 "서비스 A" 하나이고 revision 수는 5 그대로다

  Scenario: '이 구성으로…' 메뉴에서 '새 Board 만들기…'는 '복원…' 아래에 있다
    Given 이력 탭에서 순번 4 revision을 골라 과거 구성을 보고 있다
    Then 과거 구성 띠의 '이 구성으로…' 메뉴 항목은 '복원…', '새 Board 만들기…' 순서다

  Scenario: 보관된 Board의 과거 구성 띠에서도 '새 Board 만들기…'는 켜져 있다
    Given "서비스 A"가 보관되어 있고 이력 탭에서 순번 4 revision을 골라 과거 구성을 보고 있다
    Then 과거 구성 띠의 '이 구성으로…' 메뉴에서 '새 Board 만들기…'는 켜져 있다
    And '복원…'은 꺼져 있다

  Scenario Outline: 파일 메뉴 '이 구성으로 새 Board 만들기…'는 과거 구성을 볼 때만 켜지고 시트가 열려 있으면 꺼진다
    Given <상태>
    Then 파일 메뉴 '이 구성으로 새 Board 만들기…'는 <켜짐>이고 단축키가 없다

    Examples:
      | 상태                                                   | 켜짐 |
      | 현재 구성을 보고 있다                                       | 꺼짐 |
      | 순번 4 과거 구성을 보고 있다                                  | 켜짐 |
      | 순번 4와 현재 구성을 비교하고 있다                              | 꺼짐 |
      | 보관된 Board의 순번 4 과거 구성을 보고 있다                      | 켜짐 |
      | 순번 4 과거 구성의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다    | 꺼짐 |
      | 순번 4 과거 구성의 "#4 구성으로 복원" 시트가 열려 있다             | 꺼짐 |

  Scenario: 파일 메뉴로 열어도 띠에서 연 것과 같은 시트다
    Given 이력 탭에서 순번 4 revision을 골라 과거 구성을 보고 있다
    When 파일 메뉴 '이 구성으로 새 Board 만들기…'를 실행한다
    Then "#4 구성으로 새 Board 만들기" 시트가 열리고 'Board 이름' 필드의 값은 "서비스 알파 사본"이다

  # ── 시트 ─────────────────────────────────────────────

  Scenario: 이름이 비어 있으면 '만들기'가 꺼지고 Return으로도 만들지 않는다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When 'Board 이름' 필드를 "   "로 바꾼다
    Then '만들기' 버튼은 꺼져 있다
    When Return 키를 누른다
    Then 시트는 열린 채이고 Board 목록은 "서비스 A" 하나다

  Scenario: 이름의 앞뒤 공백은 정리되어 저장된다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When 'Board 이름' 필드를 "  알파 2차  "로 바꾸고 '만들기'를 누른다
    Then Board 목록에 "알파 2차"가 있고 그 Board의 순번 1 revision의 Board 이름은 "알파 2차"다

  Scenario: '취소'하면 아무것도 저장하지 않고 과거 구성 보기가 이어진다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When 'Board 이름' 필드를 "버릴 이름"으로 바꾸고 '취소'를 누른다
    Then 시트가 닫히고 가운데 영역은 "서비스 A"의 순번 4 구성이며 과거 구성 띠가 보인다
    And Board 목록은 "서비스 A" 하나이고 "서비스 A"의 revision 수는 5 그대로다

  Scenario: 시트의 키보드와 접근성: Return은 '만들기', Esc는 '취소', 제목·부제·이름 필드·안내가 읽힌다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    Then '만들기'가 기본 버튼이고 Return 키는 '만들기'와 같다
    And Esc 키는 '취소'와 같다
    And VoiceOver는 시트 제목, 부제, 'Board 이름' 필드, 안내를 차례로 읽는다
    And 시트가 열려 있는 동안 '이 구성으로…' 메뉴와 파일 메뉴의 만들기 명령은 다시 열리지 않는다
    And 시트가 열려 있는 동안 파일 메뉴 '이 구성으로 복원…'도 꺼져 있다

  Scenario: 저장 중에는 확정을 한 번만 받는다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When '만들기'를 누르고, 저장이 끝나기 전에 다시 '만들기'를 누른다
    Then 저장 중에는 '만들기'와 '취소'가 꺼져 있다
    And Board 목록에는 "서비스 알파 사본"이 하나만 생긴다

  # ── 확정 ─────────────────────────────────────────────

  @A09
  Scenario: '만들기'를 확정하면 입력한 이름과 그 revision 구성으로 새 Board가 생기고 선택된다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When 'Board 이름' 필드를 "서비스 B"로 바꾸고 '만들기'를 누른다
    Then 저장이 성공한 뒤 시트가 닫히고 Board 목록은 "서비스 A", "서비스 B"다
    And "서비스 B"가 선택되고 가운데 영역은 "서비스 B"의 현재 구성이며 과거 구성 띠가 없다
    And "서비스 B"의 revision은 순번 1 하나이고 원인은 duplicated이며 복원 출처가 없다
    And "서비스 B"의 만든 시각과 순번 1의 기록 시각은 만들기를 확정한 시각(주입 시계)이고 "서비스 A" 순번 4의 기록 시각이 아니다
    And 순번 1의 Board 이름은 "서비스 B"다
    And 순번 1의 Node 구성은 "서비스 A" 순번 4 구성과 구조가 같다: 항목마다 종류·표시 이름·부모 관계·형제 순서·URL·아이콘·당시 경로가 같다
    And 이력 탭의 순번 1 행 원인 문구는 "과거 구성에서 만듦"이고 이력 탭의 "현재 구성" 행이 골라져 있다

  @A09
  Scenario: 새 Board와 Node는 새 UUID를 쓰고 부모 관계는 새 ID로 재매핑된다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When '만들기'를 누른다
    Then 새 Board의 ID는 "서비스 A"의 ID와 다르다
    And 새 Board 순번 1의 Node ID는 모두 새 값이고 "서비스 A"의 어느 revision의 Node ID와도 겹치지 않는다
    And 새 Board에서 "명세"와 "notes.md"의 부모는 새 Board의 "개발" Node ID다

  Scenario: 새 Board는 원본 Board와 revision을 출처로 기록한다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When '만들기'를 누른다
    Then 새 Board의 출처는 종류 duplicate, 원본 Board "서비스 A", 원본 revision 순번 4다
    And 새 Board는 보관되어 있지 않다

  @A09
  Scenario: 원본 Board의 이력·체크포인트·현재 구성은 그대로이고 새 Board에는 체크포인트가 없다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When '만들기'를 누른다
    Then "서비스 A"의 revision 수는 5이고 현재 revision은 순번 5이며 순번 1부터 5까지 원인·구성·기록 시각이 그대로다
    And 체크포인트 "1차 정리"는 "서비스 A" 순번 3에 그대로 붙어 있고 새 Board의 체크포인트 수는 0이다

  @A09
  Scenario: 만든 뒤 원본과 새 Board의 편집은 서로 영향을 주지 않는다
    Given 순번 4 구성으로 새 Board "서비스 B"를 만들었다
    When "서비스 A"의 현재 구성에 Wing "임시"를 더한다
    And "서비스 B"의 Board 이름을 "서비스 B2"로 바꾸고 "서비스 B"의 "문서"를 제거한다
    Then "서비스 A"의 revision 수는 6이고 "서비스 A"의 현재 구성에 Wing "문서"가 있으며 Board 이름은 "서비스 A"다
    And "서비스 B2"의 revision 수는 3이고 "서비스 B2"의 현재 구성에 Wing "임시"가 없다

  Scenario: 새 Board에서 연결 대상을 바꾸면 새 참조가 생기고 원본의 참조는 그대로다
    Given 순번 4 구성으로 새 Board "서비스 B"를 만들었다
    When "서비스 B"의 "backend"의 연결 대상을 /dev/api-v3로 바꾼다
    Then "서비스 B"의 "backend"는 새 참조 R4를 쓰고 참조 레코드는 R1, R2, R3, R4 넷이다
    And "서비스 A"의 현재 구성과 순번 4 구성의 "backend"는 각각 참조 R2를 그대로 쓴다

  # ── 참조 (Q-W21-1=A 확정: 참조 레코드 공유) ─────────────────

  Scenario: 새 Board의 항목은 원본 revision이 기록한 참조 레코드를 그대로 쓰고 새 참조 레코드를 만들지 않는다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When '만들기'를 누른다
    Then 새 Board 순번 1의 "backend"는 참조 R2를, "notes.md"는 참조 R3을 쓴다
    And 참조 레코드는 R1, R2, R3 그대로 셋이다
    And 새 Board 순번 1의 "backend"의 당시 경로는 /dev/api-v2다

  Scenario: 한쪽 Board에서 같은 대상의 접근 정보를 갱신하면 같은 참조를 쓰는 다른 Board에서도 그 접근 정보가 보인다
    Given 순번 4 구성으로 새 Board "서비스 B"를 만들었다
    And 참조 R2의 대상이 /dev/api-v2에서 /dev/moved-api로 옮겨져 북마크가 stale이다
    When "서비스 B"에서 "backend"를 골라 상태를 확인한다
    Then 참조 R2의 마지막 해석 경로는 /dev/moved-api이고 revision은 어느 Board에도 생기지 않는다
    And "서비스 A"의 "backend"를 고르면 현재 위치 /dev/moved-api가 보이고 당시 경로는 /dev/api-v2 그대로다

  # ── 보관·접근 불가·실패 ───────────────────────────────────

  Scenario: 보관된 Board의 과거 구성으로도 새 Board를 만들 수 있고 원본은 보관 상태로 남는다
    Given "서비스 A"가 보관되어 있고 이력 탭에서 순번 4 revision을 골라 과거 구성을 보고 있다
    When '이 구성으로…' 메뉴에서 '새 Board 만들기…'를 고르고 '만들기'를 누른다
    Then Board 목록에 "서비스 알파 사본"이 있고 보관되어 있지 않으며 선택되어 있다
    And "서비스 A"는 보관된 채이고 revision 수는 5 그대로다

  Scenario: 지금 접근할 수 없는 항목도 제외하지 않고 복사하며 만들기 과정에서 파일 접근과 해석이 일어나지 않는다
    Given 참조 R2의 대상 /dev/api-v2는 지금 없다
    And 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When '만들기'를 누른다
    Then 새 Board 순번 1에 "backend"가 참조 R2로 있다
    And 시트가 열린 때부터 새 Board가 선택되기까지 파일 시스템 접근과 접근 정보 해석은 한 번도 일어나지 않는다
    When 새 Board에서 "backend"를 고른다
    Then "backend"에 연결 상태 "대상 없음"이 기호와 문구로 보이고 '다시 선택…'과 '상태 새로고침'을 쓸 수 있다

  Scenario: 만들기는 연결 대상 원본 파일·폴더를 읽거나 바꾸지 않는다
    Given 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When '만들기'를 누른다
    Then 만들기 과정에서 파일 시스템 쓰기와 연결 대상 열기는 한 번도 일어나지 않는다
    And /dev/legacy-api, /dev/api-v2, notes.md 대상의 내용은 그대로다

  Scenario: 저장이 실패하면 새 Board가 생기지 않고 시트는 입력을 유지한 채 저장 실패를 알린다
    Given 저장소가 다음 저장에서 실패하도록 주입되어 있다
    And 순번 4 revision의 "#4 구성으로 새 Board 만들기" 시트가 열려 있다
    When 'Board 이름' 필드를 "서비스 B"로 바꾸고 '만들기'를 누른다
    Then Board 목록은 "서비스 A" 하나이고 저장소에 새 Project와 revision이 없다
    And 시트는 열린 채 "서비스 B"를 유지하고 저장하지 못했다는 안내를 보인다
    And 가운데 영역은 "서비스 A"의 순번 4 과거 구성 보기가 이어진다
    When 저장소가 정상으로 돌아온 뒤 '만들기'를 다시 누른다
    Then Board 목록은 "서비스 A", "서비스 B"다

  Scenario: 복제로 만든 Board의 구성으로 다시 새 Board를 만들면 출처는 그 Board와 revision이다
    Given 순번 4 구성으로 새 Board "서비스 B"를 만들었다
    And "서비스 B"의 이력 탭에서 순번 1 revision을 골라 과거 구성을 보고 있다
    When '이 구성으로…' 메뉴에서 '새 Board 만들기…'를 고르고 이름 "서비스 C"로 '만들기'를 누른다
    Then "서비스 C"의 출처는 종류 duplicate, 원본 Board "서비스 B", 원본 revision 순번 1이다
    And "서비스 C" 순번 1의 Node ID는 "서비스 A"·"서비스 B"의 어느 Node ID와도 겹치지 않는다

  # ── Domain: ID 재매핑 ───────────────────────────────────

  @A09
  Scenario Outline: ID 재매핑은 구조를 보존하고 새 ID만 쓰는 순수 함수다
    Given 구성 <구성>과 새 이름 "복사본"이 있다
    When 주입된 ID 생성기로 구성을 복사한다
    Then 결과의 Board 이름은 "복사본"이고 Node 수는 원본과 같다
    And 결과의 Node ID는 모두 생성기가 준 값이고 원본의 어느 Node ID와도 겹치지 않는다
    And 항목마다 종류·표시 이름·형제 순서·URL·아이콘·참조 ID·당시 경로가 원본과 같고 부모는 원본 부모에 대응하는 새 ID다
    And 결과는 트리 규칙 검사(순환 없음, 형제 순서 빈틈 없음, 연결 폴더 아래 자식 없음)를 통과한다
    And 같은 생성기 순서로 다시 복사하면 같은 결과다

    Examples:
      | 구성                                                   |
      | 비어 있음                                                |
      | 최상위 Bishop 하나                                         |
      | Wing 안에 Wing, 그 안에 웹 링크·Bishop 파일(아이콘 있음)이 있는 3단 중첩 |
      | 최상위 형제 다섯 개의 순서가 섞여 저장된 구성                         |

  Scenario: ID 재매핑은 원본 구성을 바꾸지 않는다
    Given 3단 중첩 구성이 있다
    When 구성을 복사한다
    Then 원본 구성의 Node ID·부모·순서는 복사 전과 같다

  # ── 서비스 경계 ─────────────────────────────────────────

  Scenario Outline: 서비스는 만들기 요청을 결정표 duplicate_request_outcome으로 판정하고 첫 번째로 맞는 규칙의 outcome을 돌려준다
    Given new_name이 <new_name>, source_project가 <source_project>, source_revision이 <source_revision>, source_board_state가 <source_board_state>다
    When 서비스에 새 Board 만들기를 요청한다
    Then outcome은 <outcome>이고 Project와 revision은 outcome이 created일 때만 하나씩 늘어난다

    Examples:
      | new_name | source_project | source_revision | source_board_state | outcome                      |
      | blank    | found          | found           | active             | rejected_blank_name          |
      | blank    | not_found      | unreadable      | archived           | rejected_blank_name          |
      | valid    | not_found      | found           | active             | rejected_project_not_found   |
      | valid    | found          | not_found       | active             | rejected_revision_not_found  |
      | valid    | found          | other_board     | archived           | rejected_revision_not_found  |
      | valid    | found          | unreadable      | active             | error_source_unreadable      |
      | valid    | found          | found           | active             | created                      |
      | valid    | found          | found           | archived           | created                      |

  Scenario: 새 Project와 첫 revision은 한 저장 단위로 커밋되고 실패하면 둘 다 남지 않는다
    Given 저장소가 다음 저장에서 실패하도록 주입되어 있다
    When 서비스에 "서비스 A" 순번 4로 "서비스 B" 만들기를 요청한다
    Then 결과는 저장 실패이고 저장소의 Project 수는 1, "서비스 A"의 revision 수는 5, 참조 레코드는 셋 그대로다

  Scenario: 없는 revision이나 다른 Board의 revision을 원본으로 주면 거부된다
    Given Board "서비스 Z"의 revision X가 있다
    When 서비스에 "서비스 A"의 원본 revision으로 X 또는 없는 ID를 준다
    Then 결과는 거부(revision_not_found)이고 Project 수는 2 그대로다

  Scenario: 원본 revision의 스냅샷을 읽을 수 없으면 만들지 않고 오류를 알린다
    Given 순번 4 revision의 구성 JSON이 손상되어 디코딩할 수 없다
    When 서비스에 "서비스 A" 순번 4로 "서비스 B" 만들기를 요청한다
    Then 결과는 원본 구성 읽기 오류이고 빈 구성으로 새 Board를 만들지 않으며 Project 수는 1 그대로다

  Scenario: 서비스는 보관된 원본 Board의 요청을 거부하지 않는다
    Given "서비스 A"가 보관되어 있다
    When 서비스에 "서비스 A" 순번 4로 "서비스 B" 만들기를 요청한다
    Then 결과는 created이고 "서비스 B"는 보관되어 있지 않다
