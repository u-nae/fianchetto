@task-W11
Feature: W11 그룹과 웹 링크 만들기, 이름·URL 편집
  가상 그룹과 웹 링크를 만들고, 항목의 표시 이름과 웹 링크의 URL을 바꾼다. 확정한 작업 하나마다 W05 서비스로 revision 하나를 남긴다.
  입력 중간 상태·같은 값 확정·유효하지 않은 입력·취소는 기록하지 않는다(PRD §6-A, §7). 웹 링크는 HTTP/HTTPS URL이며 프리뷰를 가져오지 않는다(0002).
  새 항목의 위치는 Bishop 추가와 같다: 그룹을 선택했으면 그 안, 다른 항목을 선택했으면 그 부모, 선택이 없으면 최상위의 끝(W08).
  보관된 Board에서는 모든 편집이 안내만 하고 기록하지 않는다(0009). 그룹은 실제 디렉토리를 만들지 않는다.
  시나리오는 임시 디렉토리의 실제 저장소를 쓴다.

  Background:
    Given Board "서비스 A"에 그룹 "개발"과 그 안의 Bishop "backend", 최상위 웹 링크 "API 명세"(https://example.com/api)가 있고 선택돼 있다

  # ── 그룹 ────────────────────────────────────────────────

  @A01
  Scenario Outline: 그룹을 만들면 선택한 위치의 끝에 revision 하나로 추가된다
    Given 트리에서 <선택>을 선택했다
    When "그룹 추가"에서 이름 "  공통 "을 확정한다
    Then 원인 addGroup인 revision이 하나 늘고 그룹 "공통"이 <위치>의 끝에 있다
    And 임시 디렉토리에 새 파일이나 디렉토리가 생기지 않는다

    Examples:
      | 선택               | 위치        |
      | 아무 항목도 없음    | 최상위      |
      | 그룹 "개발"        | 그룹 "개발" |
      | Bishop "backend"   | 그룹 "개발" |

  @A01
  Scenario: 그룹 안에 그룹을 여러 단계로 만들 수 있다
    When 그룹 "개발" 안에 그룹 "하위"를, 그 안에 그룹 "더 하위"를 만든다
    Then "개발" > "하위" > "더 하위"로 중첩되고 revision이 두 개 늘어난다

  # ── 웹 링크 ─────────────────────────────────────────────

  Scenario: 웹 링크를 만들면 이름과 정리한 URL로 revision 하나가 남는다
    When "웹 링크 추가"에서 이름 "디자인 시안", URL " https://figma.com/file/1 "을 확정한다
    Then 원인 addWebLink인 revision이 하나 늘고 최상위 끝에 웹 링크 "디자인 시안"(https://figma.com/file/1)이 있다

  Scenario Outline: 웹 링크 입력이 유효하지 않으면 입력을 유지하고 이유를 알린다
    When "웹 링크 추가"에서 이름 <이름>, URL <URL>을 확정한다
    Then 입력 창은 열린 채 입력을 유지하고 <안내>를 보여 준다
    And revision 수는 그대로다

    Examples:
      | 이름          | URL                   | 안내                                  |
      | "디자인 시안" | "ftp://example.com"   | http 또는 https 주소가 필요하다는 안내    |
      | "디자인 시안" | "example.com"         | http 또는 https 주소가 필요하다는 안내    |
      | "디자인 시안" | ""                    | http 또는 https 주소가 필요하다는 안내    |
      | "   "         | "https://figma.com"   | 이름이 필요하다는 안내                  |

  # ── 이름 변경 ───────────────────────────────────────────

  @A04
  Scenario Outline: 항목 이름을 바꾸면 UUID와 위치는 그대로이고 과거 revision은 옛 이름을 가진다
    Given 트리에서 <항목>을 선택했다
    When "이름 변경"에서 이름 "새 이름"을 확정한다
    Then 원인 renameNode인 revision이 하나 늘고 그 항목의 표시 이름은 "새 이름"이다
    And 그 항목의 UUID·부모·정렬 순서와 연결 대상·URL은 그대로다
    And 직전 revision의 그 항목은 옛 이름을 가진다

    Examples:
      | 항목              |
      | 그룹 "개발"        |
      | Bishop "backend"  |
      | 웹 링크 "API 명세" |

  @A04
  Scenario Outline: 이름 변경을 같은 값으로 확정하거나 빈 이름이면 기록하지 않는다
    Given 트리에서 Bishop "backend"를 선택했다
    When "이름 변경"에서 이름 <이름>을 확정한다
    Then <결과>이고 revision 수는 그대로다

    Examples:
      | 이름          | 결과                                         |
      | " backend "   | 입력 창이 닫히고 표시 이름은 "backend"          |
      | "   "         | 입력 창이 열린 채 이름이 필요하다는 안내가 보임  |

  # ── URL 변경 ────────────────────────────────────────────

  @A04
  Scenario: 웹 링크 URL을 바꾸면 UUID와 이름은 그대로이고 revision 하나가 남는다
    Given 트리에서 웹 링크 "API 명세"를 선택했다
    When "URL 변경"에서 URL "https://example.com/v2"를 확정한다
    Then 원인 changeURL인 revision이 하나 늘고 "API 명세"의 URL은 "https://example.com/v2"이며 UUID와 이름은 그대로다
    And 직전 revision의 "API 명세" URL은 "https://example.com/api"다

  Scenario Outline: URL 변경을 같은 값으로 확정하거나 유효하지 않은 URL이면 기록하지 않는다
    Given 트리에서 웹 링크 "API 명세"를 선택했다
    When "URL 변경"에서 URL <URL>을 확정한다
    Then <결과>이고 revision 수는 그대로다

    Examples:
      | URL                          | 결과                                                  |
      | " https://example.com/api "  | 입력 창이 닫힘                                         |
      | "ftp://example.com"          | 입력 창이 열린 채 http 또는 https 주소가 필요하다는 안내가 보임 |

  Scenario Outline: URL 변경은 웹 링크를 선택했을 때만 시작한다
    Given 트리에서 <선택>을 선택했다
    When "URL 변경"을 실행한다
    Then 입력 창을 열지 않는다

    Examples:
      | 선택               |
      | 그룹 "개발"         |
      | Bishop "backend"   |
      | 아무 항목도 없음     |

  # ── 공통 ────────────────────────────────────────────────

  Scenario Outline: 입력 창을 취소하면 아무것도 기록하지 않는다
    When <동작>의 입력 창에 값을 넣고 취소한다
    Then revision 수는 그대로다

    Examples:
      | 동작          |
      | "그룹 추가"    |
      | "웹 링크 추가" |
      | "이름 변경"    |
      | "URL 변경"     |

  Scenario Outline: 저장이 실패하면 입력을 유지하고 저장하지 못했다고 알린다
    Given 다음 저장 직전에 실패하도록 설정되어 있다
    When <동작>에서 유효한 값을 확정한다
    Then 입력 창은 열린 채 입력을 유지하고 저장하지 못했다는 안내를 보여 주며 revision 수는 그대로다

    Examples:
      | 동작          |
      | "그룹 추가"    |
      | "웹 링크 추가" |
      | "이름 변경"    |
      | "URL 변경"     |

  Scenario Outline: 보관된 Board에서는 편집을 시작하지 않고 안내한다
    Given 보관된 Board "옛 프로젝트"의 항목이 선택돼 있다
    When <동작>을 실행한다
    Then 입력 창을 열지 않고 보관된 Board는 바꿀 수 없다는 안내를 보여 준다

    Examples:
      | 동작          |
      | "그룹 추가"    |
      | "웹 링크 추가" |
      | "이름 변경"    |
      | "URL 변경"     |

  Scenario: 편집 명령이 메뉴에 있고 화면 문구가 정해진 용어를 쓴다
    When 앱 메뉴를 확인한다
    Then 파일 메뉴에 "그룹 추가…", "웹 링크 추가…"가, 편집 메뉴에 "이름 변경…", "URL 변경…"이 있다
    And String Catalog에 "그룹 추가", "웹 링크 추가", "이름 변경", "URL 변경" 문구가 있다
