@task-W18
Feature: W18 과거 구성 읽기 전용 보기와 당시 대상 열기
  이력 탭(W17)에서 revision을 고르면 가운데 영역이 그 자리에서 그 revision의 구성으로 바뀌고 위에 과거 구성 띠가 붙는다(0019, DESIGN.md 16.1·16.3).
  과거 구성은 읽기 전용이다(16.4). 과거 항목을 열면 그 항목의 reference가 지금 해석하는 대상을 연다(PRD §6-D, 0003).
  당시 경로와 현재 위치가 다르면 둘을 구분해 보이고, 열리는 것은 지금의 파일이라는 안내를 둔다. 당시 존재 여부를 단정하지 않는다.
  과거 화면의 다시 선택은 같은 대상의 접근 복구만 허용하고 다른 대상으로 덮어쓰지 않는다(PRD §6-H, 0012).
  조회·열기·접근 복구는 revision을 만들지 않는다(PRD §7). 과거와 현재를 색만으로 구분하지 않는다.

  Background:
    Given Board "서비스 A"의 revision이 다음과 같다
      | 순번 | 원인            | 구성                                                                 |
      | 1   | created        | 비어 있음                                                             |
      | 2   | addLinkedItems | 최상위에 Bishop 폴더 "backend"(참조 R1, 당시 경로 /dev/legacy-api)와 Wing "개발" |
      | 3   | replaceTarget  | "backend"가 참조 R2(당시 경로 /dev/api-v2)를 쓴다                          |
      | 4   | addGroup       | Wing "문서"를 더했다                                                   |
    And 현재 revision은 순번 4다
    And 시스템 시간대는 Asia/Seoul이고 순번 2는 2026-10-03 14:20에 기록되었다

  # ── 과거 구성 보기 ─────────────────────────────────────

  @A06
  Scenario: revision을 고르면 가운데 영역이 그 revision의 구성으로 바뀌고 과거 구성 띠가 붙는다
    When 이력 탭에서 순번 2 revision을 고른다
    Then 가운데 영역의 항목은 "backend", "개발"이고 "문서"는 없다
    And 과거 구성 띠의 첫 줄은 "과거 구성 · 읽기 전용"과 '현재로 돌아가기'다
    And 과거 구성 띠의 둘째 줄은 "#2 · 2026년 10월 3일 오후 2:20 기록"이다
    And 과거 구성 띠의 접근성 라벨은 "과거 구성, 읽기 전용, #2, 2026년 10월 3일 오후 2:20 기록"이다

  Scenario: 아이콘 보기에서도 같은 과거 구성과 띠를 보이고 Wing 탐색은 그대로 쓴다
    Given 구성 영역이 아이콘 보기다
    When 이력 탭에서 순번 2 revision을 고른다
    Then 아이콘 보기의 타일은 "backend", "개발"이고 과거 구성 띠가 보인다
    When Wing "개발"로 들어갔다가 상위로 나온다
    Then 과거 구성 띠는 그대로 보이고 타일은 "backend", "개발"이다

  Scenario: 아이콘 보기 위치의 Wing이 고른 revision에 없으면 있는 곳까지만 남긴다
    Given 구성 영역이 아이콘 보기이고 현재 구성의 Wing "문서" 안을 보고 있다
    When 이력 탭에서 순번 2 revision을 고른다
    Then 아이콘 보기는 최상위를 보인다

  Scenario Outline: 현재 구성으로 돌아가는 방법은 세 가지다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When <방법>
    Then 가운데 영역은 현재 구성("backend", "개발", "문서")이고 과거 구성 띠가 없다
    And 이력 탭의 "현재 구성" 행이 골라져 있다

    Examples:
      | 방법                                         |
      | 과거 구성 띠의 '현재로 돌아가기'를 누른다             |
      | 이력 탭의 "현재 구성" 행을 고른다                   |
      | 보기 메뉴 '현재 구성으로 돌아가기'를 실행한다          |

  Scenario: 과거 구성을 보지 않을 때는 '현재 구성으로 돌아가기'가 꺼져 있다
    Given 현재 구성을 보고 있다
    Then 보기 메뉴 '현재 구성으로 돌아가기'는 꺼져 있다

  Scenario: 이력 탭을 닫아도 과거 구성 보기는 이어지고 띠로 돌아갈 수 있다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When 항목 탭으로 바꾼다
    Then 가운데 영역은 순번 2 구성이고 과거 구성 띠가 보인다

  Scenario: 다른 Board를 고르면 그 Board의 현재 구성으로 돌아간다
    Given Board "서비스 B"가 있고 "서비스 A"의 순번 2 revision을 골라 과거 구성을 보고 있다
    When "서비스 B"를 고른다
    Then 가운데 영역은 "서비스 B"의 현재 구성이고 과거 구성 띠가 없다

  Scenario: 과거 구성 보기는 다시 실행하면 이어지지 않는다
    Given 순번 2 revision을 골라 과거 구성을 보던 채 앱을 끝냈다
    When 앱을 다시 연다
    Then 가운데 영역은 현재 구성이고 과거 구성 띠가 없다

  Scenario Outline: 과거와 현재를 오갈 때 고른 항목은 보이는 구성에 있으면 남고 없으면 비워진다
    Given <처음 구성>에서 "<항목>"을 골라 두었다
    When <바꾸기>
    Then 고른 항목은 <결과>다

    Examples:
      | 처음 구성    | 항목      | 바꾸기                         | 결과        |
      | 현재 구성    | backend | 이력 탭에서 순번 2 revision을 고른다  | "backend"  |
      | 현재 구성    | 문서     | 이력 탭에서 순번 2 revision을 고른다  | 없음        |
      | 순번 2 구성  | 개발     | 현재로 돌아간다                    | "개발"      |

  # ── 읽기 전용 ─────────────────────────────────────────

  @A06
  Scenario: 과거 구성에서는 구성을 바꾸는 동작이 모두 꺼진다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있고 "backend"를 골랐다
    Then Bishop 추가·Wing 추가·웹 링크 추가·이름 변경·URL 변경·이동·위로 이동·아래로 이동·제거·연결 대상 변경·아이콘 고르기·Board 이름 변경이 모두 꺼져 있다
    And 앱 안 끌어다 놓기와 Finder에서 끌어온 파일 받기를 받지 않는다
    And Delete 키로 제거 확인 창이 열리지 않는다

  Scenario: 과거 구성에서 이름이나 위치를 바꾸려 해도 revision이 생기지 않는다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When "backend"를 Wing "개발" 위로 끌어다 놓거나 이름 변경을 시도한다
    Then "서비스 A"의 revision 수는 4이고 현재 revision은 순번 4 그대로다

  Scenario Outline: 과거 구성의 오른쪽 클릭 메뉴는 열기·Finder에서 보기·다시 선택만 둔다
    Given 이력 탭에서 순번 2 revision을 골라 과거 구성을 보고 있다
    When <항목>을 오른쪽 클릭한다
    Then 메뉴 항목은 <메뉴>다

    Examples:
      | 항목                    | 메뉴                                  |
      | Bishop "backend"        | 열기, Finder에서 보기, 다시 선택…          |
      | 웹 링크                  | 열기                                   |
      | Wing "개발"(목록 보기)     | 없음                                   |
      | Wing "개발"(아이콘 보기)   | 들어가기                                |

  Scenario: 과거 구성의 Bishop 용도 배지는 당시 값으로 보이고 아이콘 고르기는 꺼진다
    Given 순번 2에서 "backend"의 용도는 code였고 현재 구성에서는 data다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 고른다
    Then "backend"의 기호는 code 용도 배지이고 인스펙터의 아이콘 고르기는 꺼져 있다

  # ── 과거 항목 열기와 위치 ─────────────────────────────────

  @A06
  Scenario: 대상 교체 뒤 과거 항목을 열면 그 revision의 reference가 지금 해석하는 대상을 연다
    Given 참조 R1은 지금 /dev/legacy-api로, 참조 R2는 지금 /dev/api-v2로 해석된다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 연다
    Then /dev/legacy-api가 열린다
    When 현재로 돌아가 "backend"를 연다
    Then /dev/api-v2가 열린다

  @A06
  Scenario: 과거 항목 Finder에서 보기도 그 revision의 reference로 한다
    Given 참조 R1은 지금 /dev/legacy-api로 해석된다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 Finder에서 보여 준다
    Then Finder에 /dev/legacy-api가 선택되어 보인다

  @A06
  Scenario Outline: '고른 항목' 카드는 당시 경로와 현재 위치를 보이고 다르면 구분해 알린다
    Given 참조 R1의 대상이 지금 <현재 해석>
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 고른다
    Then '고른 항목' 카드의 이름은 "backend"이고 당시 경로는 "/dev/legacy-api"다
    And 현재 위치 줄은 <현재 위치>다
    And "당시와 다른 위치" 표시는 <다른 위치>다

    Examples:
      | 현재 해석                        | 현재 위치                | 다른 위치 |
      | /dev/legacy-api로 해석된다         | "/dev/legacy-api"      | 없음     |
      | /archive/legacy-api로 해석된다     | "/archive/legacy-api"  | 있음     |
      | /dev/legacy-api/로 해석된다(끝 /)   | "/dev/legacy-api"      | 없음     |
      | 권한 필요로 해석되지 않는다            | 상태 "권한 필요"          | 없음     |
      | 대상 없음으로 해석되지 않는다          | 상태 "대상 없음"          | 없음     |

  @A06
  Scenario: '고른 항목' 카드는 열리는 것이 지금의 파일이라고 안내한다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 고른다
    Then '고른 항목' 카드에 "열면 지금의 파일이 열립니다. 파일 내용의 과거 버전은 보관하지 않습니다."가 보이고 '열기'와 'Finder에서 보기'가 있다

  Scenario: 웹 링크를 고르면 카드에 당시 URL을 보이고 열기는 당시 URL을 연다
    Given 순번 2의 웹 링크 "API 명세"의 URL은 https://old.example.com이고 현재 구성에서는 https://new.example.com이다
    When 이력 탭에서 순번 2 revision을 고르고 "API 명세"를 고른 뒤 연다
    Then 카드의 당시 URL은 "https://old.example.com"이고 https://old.example.com이 열린다

  Scenario: Wing을 고르면 카드에는 이름만 있고 열기 버튼이 없다
    When 이력 탭에서 순번 2 revision을 고르고 Wing "개발"을 고른다
    Then '고른 항목' 카드에는 "개발"만 있고 경로·열기·Finder에서 보기가 없다

  Scenario: 과거 구성에서 항목을 고르지 않았으면 카드가 없다
    When 이력 탭에서 순번 2 revision을 고른다
    Then '고른 항목' 카드는 보이지 않는다

  Scenario: 현재 구성을 보고 있으면 이력 탭에 '고른 항목' 카드가 없다
    Given 현재 구성에서 "backend"를 골랐다
    When 이력 탭을 연다
    Then '고른 항목' 카드는 보이지 않는다

  Scenario: 과거 항목을 열지 못하면 기존 열기 실패 안내를 보이고 기록하지 않는다
    Given 참조 R1이 볼륨 연결 필요로 해석되지 않는다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 연다
    Then 열기 실패 안내(볼륨 연결 필요)가 보이고 revision 수는 4 그대로다

  Scenario: 과거 항목의 상태는 그 revision의 reference로 확인하고 현재 구성의 상태와 섞지 않는다
    Given 현재 구성에서 "backend"(참조 R2)의 상태를 정상으로 확인했고 참조 R1은 대상 없음이다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 고른다
    Then 과거 구성의 "backend" 상태는 "대상 없음"이다
    When 현재로 돌아간다
    Then "backend"의 상태 표시는 확인 전이다

  Scenario: 과거 항목을 열거나 위치를 확인할 때 접근 정보가 새로 만들어지면 참조만 갱신하고 revision은 만들지 않는다
    Given 참조 R1의 저장된 접근 정보가 오래되어 해석할 때 새 접근 정보가 만들어진다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 연다
    Then 참조 R1의 접근 정보는 새 값이고 revision 수는 4이며 순번 2의 당시 경로는 그대로다

  # ── 과거 화면의 다시 선택 ─────────────────────────────────

  Scenario: 과거 화면의 다시 선택은 같은 대상이면 접근만 복구하고 revision을 만들지 않는다
    Given 참조 R1이 권한 필요 상태이고 사용자가 R1과 같은 대상 /dev/legacy-api를 고른다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"에서 '다시 선택…'을 한다
    Then 참조 R1의 접근 정보가 갱신되고 "backend"의 상태는 정상이다
    And revision 수는 4이고 순번 2의 참조는 R1 그대로다

  Scenario Outline: 과거 화면의 다시 선택은 다른 대상이나 판정 불가면 확인 창 없이 안내하고 아무것도 바꾸지 않는다
    Given 사용자가 고른 대상은 R1과 <판정>이다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"에서 '다시 선택…'을 한다
    Then 연결 대상 변경 확인 창은 열리지 않고 "과거 구성에서는 같은 대상의 접근만 복구할 수 있습니다." 안내가 보인다
    And 참조 R1의 접근 정보, revision 수 4, 현재 구성은 그대로다

    Examples:
      | 판정     |
      | 다른 대상 |
      | 판정 불가 |

  Scenario: 과거 화면의 다시 선택에서 종류가 다른 대상을 고르면 기존 종류 불일치 안내를 보인다
    When 이력 탭에서 순번 2 revision을 고르고 Bishop 폴더 "backend"에서 '다시 선택…'으로 파일을 고른다
    Then 종류 불일치 안내가 보이고 아무것도 바뀌지 않는다

  Scenario: 보관된 Board의 과거 화면도 같은 대상 접근 복구만 된다
    Given "서비스 A"가 보관되어 있고 사용자가 R1과 같은 대상을 고른다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"에서 '다시 선택…'을 한다
    Then 참조 R1의 접근 정보가 갱신되고 revision 수는 4 그대로다

  # ── 기록하지 않음과 문구 ─────────────────────────────────

  @A06
  Scenario: 과거 구성 보기·항목 고르기·열기·현재로 돌아가기는 revision을 만들지 않는다
    When 이력 탭에서 순번 2 revision을 고르고 "backend"를 골라 연 뒤 현재로 돌아간다
    Then "서비스 A"의 revision 수는 4이고 현재 revision은 순번 4다

  Scenario: 과거 구성 관련 문구는 String Catalog에 있다
    Then String Catalog에 "과거 구성 · 읽기 전용", "현재로 돌아가기", "현재 구성으로 돌아가기", "#%lld · %@ 기록", "과거 구성, 읽기 전용, #%lld, %@ 기록", "고른 항목", "당시 경로", "현재 위치", "당시와 다른 위치", "당시 URL", "열면 지금의 파일이 열립니다. 파일 내용의 과거 버전은 보관하지 않습니다.", "과거 구성에서는 같은 대상의 접근만 복구할 수 있습니다." 키가 있다
