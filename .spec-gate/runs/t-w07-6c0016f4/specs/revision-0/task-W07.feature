@task-W07
Feature: W07 기본 창과 Board 탐색
  기본 창은 왼쪽 Board 목록, 가운데 선택한 Board의 현재 구성 트리, 오른쪽 상세 영역으로 이뤄진다.
  화면 상태 모델(@MainActor)은 저장소를 MainActor 밖에서 열고, Board 만들기는 W05 서비스로 커밋한다.
  화면 용어는 String Catalog에만 둔다: Board, Board 만들기, 보관된 Board, Bishop, 그룹, 웹 링크(0006).
  저장소를 열 수 없으면 빈 저장소로 바꾸지 않고 원인과 복구 선택지(다시 시도·저장소 위치를 Finder에서 보기·종료)를 보여 준다(Q-W07-1).
  화면 상태 시나리오는 임시 디렉토리의 실제 저장소와 주입된 시계·UUID·마지막 Board 기록·Finder·종료 동작을 쓴다.

  # ── 첫 실행과 Board 만들기 ──────────────────────────────

  Scenario: 첫 실행에는 빈 Board 목록과 Board 만들기 동작을 보여 준다
    Given 저장소에 Board가 없다
    When 기본 창을 연다
    Then Board 목록은 비어 있고 선택된 Board가 없다
    And 가운데 영역은 Board가 없다는 안내와 "Board 만들기" 동작을 보여 준다

  @A01
  Scenario: Board를 만들면 목록에 나타나고 선택되며 빈 현재 구성을 보여 준다
    Given 저장소에 Board가 없다
    When "Board 만들기"에서 이름 "서비스 A"를 확정한다
    Then 저장이 성공한 뒤 Board 목록에 "서비스 A"가 있다
    And "서비스 A"가 선택되고 가운데 영역은 Node가 없는 현재 구성을 보여 준다
    And 만들기 입력 창은 닫힌다

  Scenario Outline: Board를 만들지 못하면 입력을 유지하고 이유를 보여 준다
    Given 저장소에 Board가 없다
    And <조건>
    When "Board 만들기"에서 이름 <이름>을 확정한다
    Then 만들기 입력 창은 열린 채 입력 <이름>을 유지하고 <안내>를 보여 준다
    And Board 목록은 비어 있고 선택된 Board가 없다

    Examples:
      | 조건                                   | 이름        | 안내                         |
      | 저장소가 정상이다                       | "   "       | 이름이 필요하다는 안내        |
      | 다음 저장 직전에 실패하도록 설정되어 있다 | "서비스 A"  | 저장하지 못했다는 안내        |

  # ── 목록과 선택 ─────────────────────────────────────────

  Scenario: Board 목록은 보관된 Board를 따로 모아 보여 준다
    Given 저장소에 Board "서비스 A", "서비스 B"와 보관된 Board "옛 프로젝트"가 있다
    When 기본 창을 연다
    Then Board 목록에는 "서비스 A", "서비스 B"가 만든 순서대로 있다
    And "보관된 Board" 묶음에는 "옛 프로젝트"가 있고 행에 "보관됨"이 글자로 표시된다

  Scenario: 같은 이름의 Board는 만든 시각으로 구분해 보여 준다
    Given 저장소에 이름이 "서비스 A"인 Board 두 개가 시각 T0와 T1에 만들어져 있다
    When 기본 창을 연다
    Then 두 행은 같은 이름과 서로 다른 만든 시각을 보여 준다

  Scenario: Board를 선택하면 현재 구성을 트리로 보여 준다
    Given Board "서비스 A"의 현재 구성이 다음과 같다
      | 표시 이름 | 종류    | 부모 | 정렬 순서 |
      | 개발      | group   |      | 0         |
      | backend   | folder  | 개발 | 1         |
      | 설계 메모 | file    | 개발 | 0         |
      | API 명세  | webLink |      | 1         |
    When "서비스 A"를 선택한다
    Then 트리 최상위는 "개발", "API 명세" 순서다
    And "개발" 아래는 "설계 메모", "backend" 순서다
    And 연결 폴더 "backend"는 펼칠 하위 항목이 없다
    And 각 행은 종류를 글자로 함께 알린다: 그룹, Bishop, 웹 링크

  Scenario: 트리에서 항목을 선택하면 상세 영역에 표시 이름·종류·대상을 보여 준다
    Given Board "서비스 A"에 기록 당시 경로 "/dev/legacy-api"의 연결 폴더 "backend"와 URL "https://example.com/api"의 웹 링크 "API 명세"가 있다
    When "backend"를 선택한다
    Then 상세 영역은 표시 이름 "backend", 종류 Bishop(폴더), 경로 "/dev/legacy-api"를 보여 준다
    When "API 명세"를 선택한다
    Then 상세 영역은 표시 이름 "API 명세", 종류 웹 링크, URL "https://example.com/api"를 보여 준다

  # ── 마지막 Board 복원 ───────────────────────────────────

  Scenario Outline: 다시 열면 마지막으로 본 Board를 현재 구성으로 연다
    Given 저장소에 Board "서비스 A"와 보관된 Board "옛 프로젝트"가 있다
    And 마지막으로 선택한 Board 기록은 <기록>이다
    When 기본 창을 다시 연다
    Then 선택된 Board는 <선택>이다
    And 선택된 Board가 있으면 가운데 영역은 그 Board의 현재 구성이다

    Examples:
      | 기록                  | 선택          |
      | "서비스 A"             | "서비스 A"     |
      | "옛 프로젝트"          | "옛 프로젝트"  |
      | 지금은 없는 Board UUID | 없음          |
      | 없음                  | 없음          |

  Scenario: Board를 선택하면 마지막 Board 기록을 바꾼다
    Given 저장소에 Board "서비스 A"와 "서비스 B"가 있다
    When "서비스 B"를 선택한다
    Then 마지막 Board 기록은 "서비스 B"의 UUID다

  # ── 저장소를 열 수 없을 때 (PRD §7, Q-W07-1) ────────────

  Scenario Outline: 저장소를 열 수 없으면 원인과 복구 선택지를 보여 준다
    Given 저장소 열기가 원인 <원인>으로 실패한다
    When 기본 창을 연다
    Then Board 목록 대신 <안내>와 복구 선택지 "다시 시도", "Finder에서 보기", "종료"를 보여 준다
    And 빈 저장소를 만들거나 기존 저장소 파일을 바꾸지 않는다

    Examples:
      | 원인         | 안내                                          |
      | damaged      | 데이터를 읽을 수 없다는 안내                     |
      | incompatible | 더 새로운 버전의 앱이 만든 데이터라는 안내         |
      | accessDenied | 데이터에 접근할 권한이 없다는 안내                |
      | unavailable  | 데이터를 열지 못했다는 안내                       |

  Scenario: 다시 시도해 저장소가 열리면 Board 목록을 보여 준다
    Given 저장소 열기가 처음에는 실패하고 두 번째에는 성공하며 Board "서비스 A"가 있다
    When 기본 창을 열고 "다시 시도"를 고른다
    Then 복구 화면이 사라지고 Board 목록에 "서비스 A"가 있다

  Scenario: Finder에서 보기와 종료는 해당 동작만 한다
    Given 저장소 열기가 원인 damaged로 실패한다
    When "Finder에서 보기"를 고른다
    Then 저장소 파일 위치를 Finder에 보여 달라는 요청이 한 번 간다
    When "종료"를 고른다
    Then 앱 종료 요청이 한 번 간다

  Scenario: 저장소는 MainActor 밖에서 연다
    When 기본 창을 연다
    Then 저장소 열기 작업은 메인 스레드가 아닌 곳에서 실행된다

  # ── 메뉴·키보드·문구 ────────────────────────────────────

  @A01
  Scenario: 첫 실행에서 키보드로 Board를 만든다 (UI 테스트)
    Given 빈 테스트 전용 저장소로 앱을 실행한다
    When ⌘N을 누르고 이름 "서비스 A"를 입력한 뒤 Return을 누른다
    Then 창의 Board 목록에 "서비스 A"가 선택된 채 나타난다

  Scenario: 메뉴에 Board 만들기 명령이 있다 (UI 테스트)
    Given 빈 테스트 전용 저장소로 앱을 실행한다
    When 파일 메뉴를 연다
    Then "Board 만들기…" 항목이 단축키 ⌘N과 함께 있다

  Scenario: 화면 문구는 정해진 용어를 쓰고 구현 용어를 쓰지 않는다
    When String Catalog를 검사한다
    Then "Board 만들기", "보관된 Board", "Bishop", "그룹", "웹 링크" 문구가 있다
    And 화면 문구에 "DB", "JSON", "bookmark", "북마크", "파일 삭제"가 없다
