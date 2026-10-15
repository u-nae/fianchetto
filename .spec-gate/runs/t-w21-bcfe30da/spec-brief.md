# 명세 브리프 — W21 과거 구성에서 새 Board 만들기

## 1. 작업 항목

| task_id | title | route | acceptance_refs |
| --- | --- | --- | --- |
| W21 | 과거 구성에서 새 Board 만들기 | BOTH | A09 |

기준 문서:
- docs/PRD.md (9194c2af1e20)
- docs/TECH_STACK.md (3b623d55c2cc)

run_id: t-w21-bcfe30da

## 2. 승인된 명세

### .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature

```gherkin
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
```

### .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/W21.decision.yaml

| rule_id | new_name | source_project | source_revision | source_board_state | outcome |
| --- | --- | --- | --- | --- | --- |
| R1 | blank | (blank) | (blank) | (blank) | rejected_blank_name |
| R2 | (blank) | not_found | (blank) | (blank) | rejected_project_not_found |
| R3 | (blank) | (blank) | [not_found, other_board] | (blank) | rejected_revision_not_found |
| R4 | (blank) | (blank) | unreadable | (blank) | error_source_unreadable |
| R5 | (blank) | (blank) | found | (blank) | created |

셀 맵

| new_name | source_project | source_revision | source_board_state | rule_id |
| --- | --- | --- | --- | --- |
| valid | found | found | active | R5 |
| valid | found | found | archived | R5 |
| valid | found | not_found | active | R3 |
| valid | found | not_found | archived | R3 |
| valid | found | other_board | active | R3 |
| valid | found | other_board | archived | R3 |
| valid | found | unreadable | active | R4 |
| valid | found | unreadable | archived | R4 |
| valid | not_found | found | active | R2 |
| valid | not_found | found | archived | R2 |
| valid | not_found | not_found | active | R2 |
| valid | not_found | not_found | archived | R2 |
| valid | not_found | other_board | active | R2 |
| valid | not_found | other_board | archived | R2 |
| valid | not_found | unreadable | active | R2 |
| valid | not_found | unreadable | archived | R2 |
| blank | found | found | active | R1 |
| blank | found | found | archived | R1 |
| blank | found | not_found | active | R1 |
| blank | found | not_found | archived | R1 |
| blank | found | other_board | active | R1 |
| blank | found | other_board | archived | R1 |
| blank | found | unreadable | active | R1 |
| blank | found | unreadable | archived | R1 |
| blank | not_found | found | active | R1 |
| blank | not_found | found | archived | R1 |
| blank | not_found | not_found | active | R1 |
| blank | not_found | not_found | archived | R1 |
| blank | not_found | other_board | active | R1 |
| blank | not_found | other_board | archived | R1 |
| blank | not_found | unreadable | active | R1 |
| blank | not_found | unreadable | archived | R1 |

### .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/W21.decision.vectors.yaml

벡터 파일 (§4에 반영)

## 3. Test obligations

| obligation_id | kind | description | acceptance_refs | source |
| --- | --- | --- | --- | --- |
| W21-menu-opens-sheet | scenario | 띠 '이 구성으로…' › '새 Board 만들기…'가 "#n 구성으로 새 Board 만들기" 시트를 열고 부제·기본 이름(전체 선택)·안내·버튼을 보이며 아무것도 저장하지 않는다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#과거 구성 띠의 '이 구성으로…' 메뉴에서 '새 Board 만들기…'를 고르면 이름을 받는 시트가 열린다 |
| W21-menu-order | scenario | '이 구성으로…' 메뉴 항목은 '복원…', '새 Board 만들기…' 순서다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#'이 구성으로…' 메뉴에서 '새 Board 만들기…'는 '복원…' 아래에 있다 |
| W21-archived-menu-enabled | scenario | 보관된 Board의 띠에서 '새 Board 만들기…'는 켜지고 '복원…'은 꺼진다(0009) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#보관된 Board의 과거 구성 띠에서도 '새 Board 만들기…'는 켜져 있다 |
| W21-file-menu-enablement | scenario | 파일 메뉴 '이 구성으로 새 Board 만들기…'의 켜짐 조건 여섯 가지(현재/과거/비교 중/보관/만들기 시트 열림/복원 시트 열림)와 단축키 없음 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#파일 메뉴 '이 구성으로 새 Board 만들기…'는 과거 구성을 볼 때만 켜지고 시트가 열려 있으면 꺼진다 |
| W21-file-menu-same-sheet | scenario | 파일 메뉴로 열어도 띠에서 연 것과 같은 시트가 같은 기본 이름으로 열린다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#파일 메뉴로 열어도 띠에서 연 것과 같은 시트다 |
| W21-blank-name-disables-confirm | scenario | 공백뿐인 이름이면 '만들기'가 꺼지고 Return으로도 만들지 않는다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#이름이 비어 있으면 '만들기'가 꺼지고 Return으로도 만들지 않는다 |
| W21-name-trimmed | scenario | 이름의 앞뒤 공백을 정리해 저장한다(PRD §5) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#이름의 앞뒤 공백은 정리되어 저장된다 |
| W21-cancel-keeps-past-view | scenario | '취소'는 아무것도 저장하지 않고 원본의 과거 구성 보기를 이어 간다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#'취소'하면 아무것도 저장하지 않고 과거 구성 보기가 이어진다 |
| W21-sheet-keyboard-accessibility | scenario | Return은 '만들기', Esc는 '취소', 제목·부제·이름 필드·안내가 VoiceOver로 읽히고 시트가 열린 동안 만들기 명령은 다시 열리지 않으며 파일 메뉴 '이 구성으로 복원…'도 꺼진다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#시트의 키보드와 접근성: Return은 '만들기', Esc는 '취소', 제목·부제·이름 필드·안내가 읽힌다 |
| W21-single-confirm-while-saving | scenario | 저장 중에는 '만들기'·'취소'가 꺼지고 Board는 하나만 생긴다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#저장 중에는 확정을 한 번만 받는다 |
| W21-confirm-creates-board | scenario | 확정 시 입력한 이름과 원본 revision 구성(종류·이름·부모·순서·URL·아이콘·당시 경로)으로 순번 1(cause duplicated) 하나뿐인 새 Board가 생기고 선택되어 현재 구성을 보이며, 만든 시각과 순번 1 기록 시각은 확정 시각(주입 시계)이지 원본 revision의 시각이 아니다 | A09 | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#'만들기'를 확정하면 입력한 이름과 그 revision 구성으로 새 Board가 생기고 선택된다 |
| W21-new-ids-remapped | scenario | 새 Board ID·Node ID는 모두 새 값이고 원본의 어느 revision과도 겹치지 않으며 부모 관계는 새 ID로 재매핑된다(불변식 1·2) | A09 | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#새 Board와 Node는 새 UUID를 쓰고 부모 관계는 새 ID로 재매핑된다 |
| W21-origin-recorded | scenario | 새 Board의 origin은 (duplicate, 원본 Board, 원본 revision)이고 보관되어 있지 않다(0005) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#새 Board는 원본 Board와 revision을 출처로 기록한다 |
| W21-source-preserved | scenario | 원본의 revision 수·현재 revision·각 revision·체크포인트가 그대로이고 새 Board에는 체크포인트가 없다(불변식 4) | A09 | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#원본 Board의 이력·체크포인트·현재 구성은 그대로이고 새 Board에는 체크포인트가 없다 |
| W21-independent-editing | scenario | 만든 뒤 원본 편집은 새 Board에, 새 Board 편집(이름·제거)은 원본에 영향을 주지 않는다 | A09 | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#만든 뒤 원본과 새 Board의 편집은 서로 영향을 주지 않는다 |
| W21-replace-target-independent | scenario | 새 Board의 대상 교체는 새 참조를 만들고 원본의 현재·과거 참조는 그대로다(불변식 3) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#새 Board에서 연결 대상을 바꾸면 새 참조가 생기고 원본의 참조는 그대로다 |
| W21-shares-reference-records | scenario | (Q-W21-1=A) 새 Board의 항목은 원본 revision의 참조 ID를 그대로 쓰고 참조 레코드 수가 늘지 않으며 당시 경로를 그대로 가진다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#새 Board의 항목은 원본 revision이 기록한 참조 레코드를 그대로 쓰고 새 참조 레코드를 만들지 않는다 |
| W21-shared-access-info | scenario | (Q-W21-1=A) 한쪽 Board의 접근 정보 갱신이 같은 참조를 쓰는 다른 Board에서도 보이고 revision은 생기지 않는다(불변식 8) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#한쪽 Board에서 같은 대상의 접근 정보를 갱신하면 같은 참조를 쓰는 다른 Board에서도 그 접근 정보가 보인다 |
| W21-archived-source-allowed | scenario | 보관된 Board의 과거 구성으로 만든 새 Board는 보관되지 않은 채 선택되고 원본은 보관 상태로 남는다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#보관된 Board의 과거 구성으로도 새 Board를 만들 수 있고 원본은 보관 상태로 남는다 |
| W21-copies-unreachable-items | scenario | 접근 불가 항목도 복사하고 만들기 동안 파일 접근·해석이 없으며 고르면 "대상 없음"과 해결 동작이 보인다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#지금 접근할 수 없는 항목도 제외하지 않고 복사하며 만들기 과정에서 파일 접근과 해석이 일어나지 않는다 |
| W21-no-disk-side-effects | scenario | 만들기는 파일 시스템 쓰기·연결 대상 열기를 하지 않고 원본 내용이 그대로다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#만들기는 연결 대상 원본 파일·폴더를 읽거나 바꾸지 않는다 |
| W21-save-failure-keeps-input | scenario | 저장 실패 시 Project·revision이 생기지 않고 시트가 입력을 유지한 채 안내하며 과거 구성 보기가 이어지고 재시도가 된다(PRD §7) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#저장이 실패하면 새 Board가 생기지 않고 시트는 입력을 유지한 채 저장 실패를 알린다 |
| W21-duplicate-chain | scenario | 복제로 만든 Board를 다시 복제하면 출처는 그 Board와 revision이고 ID는 어느 Board와도 겹치지 않는다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#복제로 만든 Board의 구성으로 다시 새 Board를 만들면 출처는 그 Board와 revision이다 |
| W21-remap-preserves-structure | scenario | Domain 재매핑은 빈 구성·단일·3단 중첩·섞인 순서에서 구조를 보존하고 새 ID만 쓰며 검사기를 통과하고 결정적이다 | A09 | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#ID 재매핑은 구조를 보존하고 새 ID만 쓰는 순수 함수다 |
| W21-remap-leaves-source | scenario | 재매핑은 원본 구성 값을 바꾸지 않는다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#ID 재매핑은 원본 구성을 바꾸지 않는다 |
| W21-service-outcome-table | scenario | 서비스 판정은 결정표 duplicate_request_outcome(FIRST)과 같고 created일 때만 Project·revision이 하나씩 늘어난다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#서비스는 만들기 요청을 결정표 duplicate_request_outcome으로 판정하고 첫 번째로 맞는 규칙의 outcome을 돌려준다 |
| W21-service-atomic-commit | scenario | 저장 실패 주입 시 새 Project·revision이 모두 남지 않고 참조 레코드도 그대로다(불변식 5) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#새 Project와 첫 revision은 한 저장 단위로 커밋되고 실패하면 둘 다 남지 않는다 |
| W21-service-rejects-foreign-revision | scenario | 없는 revision이나 다른 Board의 revision은 revision_not_found로 거부된다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#없는 revision이나 다른 Board의 revision을 원본으로 주면 거부된다 |
| W21-service-source-unreadable | scenario | 원본 스냅샷을 디코딩할 수 없으면 오류이고 빈 구성으로 만들지 않는다 |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#원본 revision의 스냅샷을 읽을 수 없으면 만들지 않고 오류를 알린다 |
| W21-service-allows-archived-source | scenario | 보관된 원본 Board의 요청은 거부되지 않고 새 Board는 보관되지 않는다(0009) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/task-W21.feature#서비스는 보관된 원본 Board의 요청을 거부하지 않는다 |
| W21-duplicate_request_outcome-R1 | decision-rule | 정리한 이름이 비면 다른 입력과 무관하게 rejected_blank_name |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/W21.decision.yaml#R1 |
| W21-duplicate_request_outcome-R2 | decision-rule | 원본 Board가 없으면 rejected_project_not_found |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/W21.decision.yaml#R2 |
| W21-duplicate_request_outcome-R3 | decision-rule | 원본 revision이 없거나 다른 Board면 rejected_revision_not_found |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/W21.decision.yaml#R3 |
| W21-duplicate_request_outcome-R4 | decision-rule | 원본 revision의 스냅샷을 읽거나 디코딩할 수 없으면 error_source_unreadable |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/W21.decision.yaml#R4 |
| W21-duplicate_request_outcome-R5 | decision-rule | 원본 revision을 읽었으면 보관 여부와 무관하게 created(origin duplicate, cause duplicated, 순번 1) |  | .spec-gate/runs/t-w21-bcfe30da/specs/revision-1/W21.decision.yaml#R5 |

## 4. 결정 벡터

### duplicate_request_outcome

| rule_id | obligation_id | inputs | expected |
| --- | --- | --- | --- |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=found, source_revision=found, source_board_state=active | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=found, source_revision=found, source_board_state=archived | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=found, source_revision=not_found, source_board_state=active | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=found, source_revision=not_found, source_board_state=archived | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=found, source_revision=other_board, source_board_state=active | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=found, source_revision=other_board, source_board_state=archived | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=found, source_revision=unreadable, source_board_state=active | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=found, source_revision=unreadable, source_board_state=archived | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=not_found, source_revision=found, source_board_state=active | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=not_found, source_revision=found, source_board_state=archived | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=not_found, source_revision=not_found, source_board_state=active | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=not_found, source_revision=not_found, source_board_state=archived | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=not_found, source_revision=other_board, source_board_state=active | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=not_found, source_revision=other_board, source_board_state=archived | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=not_found, source_revision=unreadable, source_board_state=active | outcome=rejected_blank_name |
| R1 | W21-duplicate_request_outcome-R1 | new_name=blank, source_project=not_found, source_revision=unreadable, source_board_state=archived | outcome=rejected_blank_name |
| R2 | W21-duplicate_request_outcome-R2 | new_name=valid, source_project=not_found, source_revision=found, source_board_state=active | outcome=rejected_project_not_found |
| R2 | W21-duplicate_request_outcome-R2 | new_name=valid, source_project=not_found, source_revision=found, source_board_state=archived | outcome=rejected_project_not_found |
| R2 | W21-duplicate_request_outcome-R2 | new_name=valid, source_project=not_found, source_revision=not_found, source_board_state=active | outcome=rejected_project_not_found |
| R2 | W21-duplicate_request_outcome-R2 | new_name=valid, source_project=not_found, source_revision=not_found, source_board_state=archived | outcome=rejected_project_not_found |
| R2 | W21-duplicate_request_outcome-R2 | new_name=valid, source_project=not_found, source_revision=other_board, source_board_state=active | outcome=rejected_project_not_found |
| R2 | W21-duplicate_request_outcome-R2 | new_name=valid, source_project=not_found, source_revision=other_board, source_board_state=archived | outcome=rejected_project_not_found |
| R2 | W21-duplicate_request_outcome-R2 | new_name=valid, source_project=not_found, source_revision=unreadable, source_board_state=active | outcome=rejected_project_not_found |
| R2 | W21-duplicate_request_outcome-R2 | new_name=valid, source_project=not_found, source_revision=unreadable, source_board_state=archived | outcome=rejected_project_not_found |
| R3 | W21-duplicate_request_outcome-R3 | new_name=valid, source_project=found, source_revision=not_found, source_board_state=active | outcome=rejected_revision_not_found |
| R3 | W21-duplicate_request_outcome-R3 | new_name=valid, source_project=found, source_revision=not_found, source_board_state=archived | outcome=rejected_revision_not_found |
| R3 | W21-duplicate_request_outcome-R3 | new_name=valid, source_project=found, source_revision=other_board, source_board_state=active | outcome=rejected_revision_not_found |
| R3 | W21-duplicate_request_outcome-R3 | new_name=valid, source_project=found, source_revision=other_board, source_board_state=archived | outcome=rejected_revision_not_found |
| R4 | W21-duplicate_request_outcome-R4 | new_name=valid, source_project=found, source_revision=unreadable, source_board_state=active | outcome=error_source_unreadable |
| R4 | W21-duplicate_request_outcome-R4 | new_name=valid, source_project=found, source_revision=unreadable, source_board_state=archived | outcome=error_source_unreadable |
| R5 | W21-duplicate_request_outcome-R5 | new_name=valid, source_project=found, source_revision=found, source_board_state=active | outcome=created |
| R5 | W21-duplicate_request_outcome-R5 | new_name=valid, source_project=found, source_revision=found, source_board_state=archived | outcome=created |

## 5. 결정

| question_id | question | answer | recommended_default | followed_recommendation |
| --- | --- | --- | --- | --- |
| Q-W21-1 | 과거 구성으로 만든 새 Board의 연결 항목은 원본과 참조 레코드를 공유할까요, 같은 북마크로 새 참조 레코드를 만들까요? | A | A | true |

결정 기록:
- docs/decisions/0036-duplicate-shares-reference-records.md

## 6. Non-blocking notes

- F-W21-10 (W21): 1차 비평이 요청한 변경 다섯 건이 모두 원문 근거와 함께 반영됐고, obligation description이 시나리오 본문과 다시 일치한다. 요청 변경이 없던 F-W21-5(Background 순번 4의 원인 묶음)·F-W21-9(결정표 확인)는 그대로 두었고 F-W21-7은 가정으로 남겼다. 회귀는 없다: 결정표 W21.decision.yaml은 revision-0과 바이트 동일하고, 벡터 파일은 table 경로만 revision-1로 바뀌었다.
- F-W21-11 (W21): 인간 답 A가 Feature 머리글·'참조' 절·가정·결정표 출력 정의·의존 시나리오 일곱 곳에 같은 뜻으로 반영됐고, 서로 모순되는 문장이 남아 있지 않다. 답이 권장안과 같아 revision-0의 본문은 바뀌지 않았고 표기만 "권장안 기준"에서 "확정"으로 바뀌었다. 미답 질문이 없으므로 author_status 전환도 맞다. 게이트 종료 뒤 이 답을 docs/decisions/로 옮기는 일은 통합 절차대로 handoff 이후에 한다.
- F-W21-12 (W21): 결정표 완전성·겹침·벡터 최신성·Gherkin 구문·obligation 양방향 대응을 산출물로 확인했다. source_revision에 읽기 실패 값(unreadable)과 규칙(R4)이 있고, 만들기는 참조 레코드를 읽지 않으므로(Q-W21-1=A) 참조 읽기 실패 입력이 없는 것이 맞다. Project 레코드 손상은 W20 board_state와 같은 관례로 표 밖의 저장소 오류다. A09(새 ID·구조와 연결 유지·원본과 독립)는 W21-new-ids-remapped, W21-confirm-creates-board, W21-source-preserved, W21-independent-editing, W21-remap-preserves-structure가 각각 깨지면 실패하는 단언으로 증명한다.
- F-W21-13 (W21): 1차 F-W21-5와 같다. 실제 편집으로는 addGroup 한 revision이 웹 링크·Bishop을 함께 더하지 못한다. fixture를 저장소에 직접 넣는 테스트에는 영향이 없고 시나리오 기대값도 맞지만, 이 Background를 UI 테스트에서 실제 편집으로 재현하면 revision 수(5)와 순번이 달라진다. 수용 경계와 무관하다.
- F-W21-14 (W21): 기본 이름 '<당시 이름> 사본'은 사이드바의 현재 이름과 다를 수 있다는 1차 참고 사항을 가정 12로 받아 디자인 세션 몫으로 넘겼다. 사용자가 이름을 입력하므로 데이터 의미는 바뀌지 않고 되돌리기 쉬워 정책 질문이 아니다. 다만 디자인 세션이 '현재 이름'으로 정하면 :31·:61·:95·:167 네 곳의 기대값 "서비스 알파 사본"이 "서비스 A 사본"으로 바뀌므로 구현 전에 확정하는 편이 TDD 왕복을 줄인다.
- F-W21-15 (W21): 1차 F-W21-4가 요청한 대로 양방향이 고정됐다. 그 결과 파일 메뉴 '이 구성으로 복원…'의 켜짐 조건 하나(만들기 시트 열림 → 꺼짐)가 W20 명세가 아니라 W21 명세에만 있다. 모순은 아니고 조건이 늘어난 것뿐이지만, 같은 명령의 켜짐 규칙이 두 작업 항목에 나뉘어 있으므로 W20 명세를 다음에 고칠 일이 있으면 outline에 같은 행을 더하는 것이 유지보수에 낫다. 지금 W21에서 고칠 것은 없다.

## 7. 검증 계약

모든 테스트의 이름 또는 태그에 그 테스트가 증명하는 obligation_id를 포함한다. /spec-cycle:verify 가 이 문자열을 찾는다.
