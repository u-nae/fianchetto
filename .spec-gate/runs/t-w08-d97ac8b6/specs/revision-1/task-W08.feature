@task-W08
Feature: W08 로컬 파일·폴더를 Bishop으로 연결하기
  사용자가 파일 선택 창이나 Finder 드롭으로 고른 파일·폴더를 한 작업으로 Board에 연결한다.
  연결 서비스는 대상마다 W06 어댑터로 읽기 전용 북마크를 만들고(MainActor 밖), W05 서비스로 revision 하나를 커밋한다.
  초기 표시 이름은 디스크의 대상 이름(마지막 경로 요소)이고, 대상 종류는 W06 판정(패키지는 file)을 따른다.
  앱은 연결 대상을 이동·복사·수정·삭제하지 않는다(불변식). Bishop은 file·folder Node의 화면 용어다(0006).
  서비스 시나리오는 임시 디렉토리의 실제 파일과 실제 저장소를 쓴다.

  # ── 연결 서비스 ─────────────────────────────────────────

  @A02
  Scenario: 여러 위치의 파일·폴더를 한 작업으로 선택 순서대로 연결한다
    Given 임시 디렉토리의 서로 다른 하위 폴더에 파일 "design.md", 폴더 "assets", 파일 "notes.txt"가 있다
    And Board "서비스 A"에 그룹 "개발"이 있다
    When 세 대상을 그 순서로 그룹 "개발"에 연결한다
    Then 결과는 committed이고 revision이 하나 늘어난다
    And 그룹 "개발" 아래에 "design.md"(Bishop 파일), "assets"(Bishop 폴더), "notes.txt"(Bishop 파일)가 그 순서로 있다
    And 각 Bishop의 기록 당시 경로는 고른 대상의 경로다
    And 각 Bishop의 참조 레코드는 해석하면 같은 대상을 가리키는 북마크를 가진다
    When 저장소를 닫고 다시 연다
    Then 세 Bishop의 참조 레코드 북마크를 해석하면 여전히 각 대상을 가리킨다

  Scenario: 패키지 폴더는 Bishop 파일로 연결한다
    Given 임시 디렉토리에 패키지 폴더 "Deck.key"가 있다
    When 그 대상을 최상위에 연결한다
    Then "Deck.key"는 Bishop 파일이다

  Scenario: 같은 대상을 한 번에 두 번 고르면 서로 다른 Bishop 두 개가 된다
    Given 임시 디렉토리에 파일 "design.md"가 있다
    When 같은 URL을 두 번 담은 선택으로 최상위에 연결한다
    Then 최상위에 "design.md" Bishop이 서로 다른 UUID와 서로 다른 참조로 두 개 있다

  Scenario: 이미 연결된 대상을 다시 연결하면 별도 Bishop을 만든다
    Given Board "서비스 A"에 파일 "design.md"를 연결한 Bishop이 있다
    When 같은 파일 "design.md"를 그룹 "개발"에 다시 연결한다
    Then 그룹 "개발"에 새 UUID와 새 참조의 Bishop "design.md"가 생기고 기존 Bishop은 그대로다

  Scenario: 고른 대상이 없으면 아무것도 기록하지 않는다
    Given Board "서비스 A"가 있다
    When 빈 선택으로 연결한다
    Then 결과는 unchanged이고 revision 수와 참조 레코드 수는 그대로다

  Scenario Outline: 대상 하나라도 북마크를 만들지 못하면 아무것도 연결하지 않고 다시 시도할 수 있다
    Given 임시 디렉토리에 파일 "design.md"와 "notes.txt"가 있다
    And <실패 조건>
    When 두 대상을 최상위에 연결한다
    Then 결과는 "연결할 수 없는 대상" 거부이고 실패한 대상 "notes.txt"를 알려 준다
    And Node·revision·참조 레코드는 하나도 생기지 않는다
    When 실패 원인을 없앤 뒤 같은 두 대상을 다시 연결한다
    Then 결과는 committed이고 Bishop 두 개가 revision 하나로 기록된다

    Examples:
      | 실패 조건                                                         |
      | 시스템 어댑터가 "notes.txt"의 북마크 생성을 실패시킨다              |
      | 고른 뒤 연결하기 전에 "notes.txt"가 지워진다(다시 시도 전에 복구) |

  Scenario: 여러 대상이 실패하면 실패한 대상을 모두 알려 준다
    Given 임시 디렉토리에 파일 "a.md", "b.md", "c.md"가 있고 "a.md"와 "c.md"는 고른 뒤 지워진다
    When 세 대상을 연결한다
    Then 거부 결과는 실패한 대상 "a.md"와 "c.md"를 선택 순서대로 알려 주고 아무것도 저장하지 않는다

  @A02
  Scenario: 연결은 대상 파일과 폴더를 바꾸지 않는다
    Given 임시 디렉토리의 파일 "design.md"와 하위 항목이 있는 폴더 "assets"의 내용·수정 시각·권한·목록을 기억한다
    When 두 대상을 연결한다
    Then 두 대상의 내용·수정 시각·권한·목록은 처음과 같고 대상 폴더들에 새 파일이 생기지 않는다

  Scenario: 저장이 실패하면 연결이 하나도 남지 않는다
    Given 임시 디렉토리에 파일 "design.md"가 있고 다음 저장 직전에 실패하도록 설정되어 있다
    When 그 대상을 연결한다
    Then 저장 실패 오류가 나고 Node·revision·참조 레코드가 생기지 않는다

  Scenario: 보관된 Board에는 연결할 수 없다
    Given 보관된 Board "옛 프로젝트"가 있다
    When 파일 하나를 연결한다
    Then 결과는 archived 거부이고 북마크를 만들지 않는다

  Scenario: 북마크 생성은 메인 스레드 밖에서 한다
    When MainActor에서 파일 하나의 연결을 요청한다
    Then 북마크 생성 호출은 메인 스레드가 아닌 곳에서 실행된다

  # ── 화면: Bishop 추가 ───────────────────────────────────

  Scenario Outline: Bishop 추가는 선택한 항목에 따라 연결할 위치를 정한다
    Given Board "서비스 A"에 그룹 "개발", 그 안의 Bishop "backend", 최상위 웹 링크 "API 명세"가 있고 선택돼 있다
    And 트리에서 <선택>을 선택했다
    When "Bishop 추가"에서 파일 "design.md"를 고른다
    Then "design.md"는 <위치>의 끝에 연결된다

    Examples:
      | 선택            | 위치        |
      | 아무 항목도 없음 | 최상위      |
      | 그룹 "개발"     | 그룹 "개발" |
      | Bishop "backend" | 그룹 "개발" |
      | 웹 링크 "API 명세" | 최상위    |

  Scenario: 파일 선택 창을 취소하면 아무것도 기록하지 않는다
    Given Board "서비스 A"가 선택돼 있다
    When "Bishop 추가"를 열고 선택 창을 취소한다
    Then revision 수는 그대로이고 안내 문구가 없다

  Scenario: Board를 선택하지 않았으면 Bishop 추가는 아무 일도 하지 않는다
    Given 선택된 Board가 없다
    When "Bishop 추가"를 실행한다
    Then 파일 선택 창을 열지 않는다

  Scenario: 연결에 실패하면 실패한 대상 이름과 다시 시도를 보여 주고, 다시 시도하면 같은 Board·같은 위치에 다시 연결한다
    Given Board "서비스 A"가 선택돼 있고 그룹 "개발"을 선택했으며 "notes.txt"의 북마크 생성이 한 번 실패한다
    When "Bishop 추가"에서 "design.md"와 "notes.txt"를 고른다
    Then 연결하지 못했다는 안내에 "notes.txt"가 있고 "다시 시도"와 "닫기"가 있다
    And 안내 문구에 구현 용어(북마크·bookmark 등)가 없다
    When 트리에서 다른 항목을 선택한 뒤 "다시 시도"를 고른다
    Then 안내가 사라지고 그룹 "개발"의 끝에 "design.md"와 "notes.txt"가 있다

  Scenario: 실패 안내를 닫으면 아무것도 기록하지 않는다
    Given 연결하지 못했다는 안내가 보인다
    When "닫기"를 고른다
    Then 안내가 사라지고 revision 수는 그대로다

  Scenario: 저장에 실패하면 저장하지 못했다는 안내와 다시 시도를 보여 준다
    Given Board "서비스 A"가 선택돼 있고 다음 저장 직전에 한 번 실패하도록 설정되어 있다
    When "Bishop 추가"에서 파일 "design.md"를 고른다
    Then 저장하지 못했다는 안내와 "다시 시도"가 보이고 revision 수는 그대로다
    When "다시 시도"를 고른다
    Then 현재 구성에 "design.md"가 있다

  Scenario: 보관된 Board에서는 Bishop 추가와 드롭이 아무것도 바꾸지 않는다
    Given 보관된 Board "옛 프로젝트"가 선택돼 있다
    When "Bishop 추가"를 실행한다
    Then 파일 선택 창을 열지 않고 보관된 Board는 바꿀 수 없다는 안내를 보여 준다
    When Finder에서 파일 "design.md"를 트리의 빈 곳에 끌어다 놓는다
    Then 드롭은 거부되고 revision이 생기지 않는다

  Scenario: 연결이 끝나면 현재 구성 트리를 새 구성으로 바꾼다
    Given Board "서비스 A"가 선택돼 있다
    When "Bishop 추가"에서 파일 "design.md"를 고른다
    Then 가운데 트리에 "design.md"가 보인다

  # ── 화면: Finder 드롭 ───────────────────────────────────

  Scenario Outline: Finder에서 끌어온 파일은 놓은 곳이 그룹이나 최상위일 때만 받는다
    Given Board "서비스 A"에 그룹 "개발", Bishop 폴더 "backend", Bishop 파일 "설계 메모", 웹 링크 "API 명세"가 있다
    When Finder에서 파일 "design.md"와 "notes.txt"를 <놓은 곳>에 끌어다 놓는다
    Then 드롭은 <결과>

    Examples:
      | 놓은 곳              | 결과                                                       |
      | 트리의 빈 곳(최상위)  | 받아들여져 두 Bishop이 최상위 끝에 revision 하나로 연결된다  |
      | 그룹 "개발"          | 받아들여져 두 Bishop이 그룹 "개발" 끝에 revision 하나로 연결된다 |
      | Bishop 폴더 "backend" | 거부되고 revision이 생기지 않는다                           |
      | Bishop 파일 "설계 메모" | 거부되고 revision이 생기지 않는다                         |
      | 웹 링크 "API 명세"    | 거부되고 revision이 생기지 않는다                           |

  Scenario: Finder에서 폴더를 끌어다 놓으면 Bishop 폴더로 연결한다
    Given Board "서비스 A"가 선택돼 있다
    When Finder에서 폴더 "assets"를 트리의 빈 곳에 끌어다 놓는다
    Then 최상위 끝에 Bishop 폴더 "assets"가 연결된다

  Scenario: 파일이 아닌 항목을 끌어다 놓으면 받지 않는다
    Given Board "서비스 A"가 선택돼 있다
    When 웹 주소 "https://example.com"이나 텍스트를 트리에 끌어다 놓는다
    Then 드롭은 거부되고 revision이 생기지 않는다

  # ── 메뉴와 문구 ─────────────────────────────────────────

  Scenario: 파일 선택 창은 파일과 폴더를 여러 개 고를 수 있다
    When Bishop 추가용 파일 선택 창 설정을 확인한다
    Then 파일 선택과 폴더 선택, 여러 개 선택이 모두 켜져 있고 새 폴더 만들기는 꺼져 있다

  Scenario: Bishop 추가 명령이 메뉴와 단축키로 있다
    When 앱 메뉴를 확인한다
    Then 파일 메뉴에 "Bishop 추가…"가 ⇧⌘A와 함께 있다
    And String Catalog에 "Bishop 추가" 문구가 있다
