@task-W28
Feature: W28 아이콘 보기와 Wing 단위 탐색
  구성 영역을 목록(트리) 보기와 아이콘 보기 중에서 고른다(0020). 아이콘 보기는 Finder처럼 한 번에 한 단계(최상위 또는 Wing 하나)의 항목을
  구성 순서대로 격자로 보이고, Wing 안으로 들어가고 나오며 탐색한다. 시각 명세는 DESIGN.md 17장·18.5를 따른다.
  두 보기는 같은 데이터·같은 명령을 쓰고, 보기 방식·현재 위치·Bishop 아이콘 설정은 화면 설정이라 revision을 만들지 않는다(PRD §7).
  배치 변경은 기존 이동 규칙(W12)과 연결 규칙(W08)을 따른다. 타일 기호는 디스크에 접근하지 않는다(0020, PRD §8 경량화).
  시나리오는 임시 디렉토리의 실제 저장소를 쓴다.

  Background:
    Given Board "서비스 A"의 최상위에 Wing "개발"(0), Bishop 파일 "README.md"(1), 웹 링크 "API 명세"(2)가 있다
    And Wing "개발" 안에 Bishop 폴더 "backend"(0), Wing "하위"(1)가 있고 "하위" 안에 Bishop 파일 "설계.key"가 있다

  # ── 전환과 기억 ─────────────────────────────────────────

  Scenario: 처음에는 목록 보기이고, 바꾼 보기는 다시 실행해도 기억한다
    Given 보기 설정이 기록된 적이 없다
    When 앱을 열면 구성 영역은 목록 보기다
    And "아이콘으로 보기"(⌘1)를 실행하고 앱을 다시 연다
    Then 구성 영역은 아이콘 보기이고 revision 수는 그대로다

  Scenario Outline: 아이콘 보기로 바꿀 때 선택한 항목이 보이는 위치에서 시작한다
    Given 목록 보기에서 <선택>
    When "아이콘으로 보기"를 실행한다
    Then 현재 위치는 <위치>이고 선택은 그대로다

    Examples:
      | 선택                                | 위치         |
      | 아무것도 선택하지 않았다                 | 최상위        |
      | Bishop "backend"를 선택했다            | Wing "개발"   |
      | Bishop 파일 "설계.key"를 선택했다        | Wing "하위"   |

  Scenario: 아이콘 보기는 현재 위치 한 단계의 항목을 구성 순서대로 보인다
    Given 아이콘 보기의 현재 위치가 최상위다
    Then 타일은 "개발", "README.md", "API 명세" 순서이고 "backend"·"하위"·"설계.key"는 보이지 않는다
    And 경로 막대는 "서비스 A"이고 오른쪽에 "항목 3개"다

  # ── 탐색 ────────────────────────────────────────────────

  Scenario Outline: Wing에 들어가면 그 Wing의 항목을 보이고 선택은 비운다
    Given 아이콘 보기의 현재 위치가 최상위이고 Wing "개발"을 선택했다
    When <동작>
    Then 현재 위치는 Wing "개발"이고 타일은 "backend", "하위" 순서이며 선택한 항목이 없다
    And 경로 막대는 "서비스 A › 개발"이고 창 제목은 "개발", 부제는 "서비스 A"다

    Examples:
      | 동작                         |
      | Wing "개발" 타일을 이중 클릭한다 |
      | "들어가기"(⌘↓)를 실행한다       |

  Scenario Outline: 위로·뒤로·경로 막대로 돌아갈 수 있다
    Given 아이콘 보기에서 최상위 → "개발" → "하위" 순서로 들어갔다
    When <동작>
    Then 현재 위치는 <위치>이고 <선택>이 선택돼 있다

    Examples:
      | 동작                               | 위치         | 선택          |
      | "상위 Wing으로"(⌘↑)를 실행한다        | Wing "개발"   | Wing "하위"    |
      | "뒤로"(⌘[)를 실행한다                | Wing "개발"   | Wing "하위"    |
      | 경로 막대의 "서비스 A"를 누른다          | 최상위        | Wing "개발"    |

  Scenario: 최상위에서는 위로·뒤로가 꺼져 있고 목록 보기에서는 위로가 꺼져 있다
    Given 아이콘 보기의 현재 위치가 최상위이고 탐색 기록이 없다
    Then "상위 Wing으로"와 "뒤로"는 실행할 수 없다
    When 목록 보기로 바꾼다
    Then "상위 Wing으로"와 "들어가기"는 실행할 수 없다

  @A02
  Scenario Outline: Bishop·웹 링크를 이중 클릭하거나 들어가기를 실행하면 연다
    Given 아이콘 보기의 현재 위치가 최상위이고 <항목>을 선택했다
    When <동작>
    Then 기본 앱 열기 요청이 <항목>의 현재 대상으로 한 번 나가고 현재 위치와 revision 수는 그대로다

    Examples:
      | 항목                  | 동작                 |
      | Bishop 파일 "README.md" | 타일을 이중 클릭한다    |
      | 웹 링크 "API 명세"      | "들어가기"(⌘↓)를 실행한다 |

  Scenario Outline: 보고 있던 Wing이 없어지면 남아 있는 가장 가까운 상위로 간다
    Given 아이콘 보기의 현재 위치가 Wing "하위"다
    When <변화>
    Then 현재 위치는 <위치>다

    Examples:
      | 변화                                     | 위치        |
      | 인스펙터에서 Wing "하위"를 제거한다            | Wing "개발"  |
      | 인스펙터에서 Wing "개발"을 제거한다            | 최상위       |
      | 다른 Board를 골랐다가 "서비스 A"로 돌아온다      | 최상위       |

  Scenario: 빈 Wing에 들어가면 빈 화면을 보이고 그곳에 끌어다 놓을 수 있다
    Given Wing "개발" 안에 빈 Wing "보관"이 있고 아이콘 보기에서 "보관"에 들어갔다
    Then "Wing이 비어 있습니다" 빈 화면과 경로 막대 "서비스 A › 개발 › 보관", "항목 0개"가 보인다
    When Finder에서 실제 파일 하나를 빈 화면에 놓는다
    Then Wing "보관"에 Bishop이 추가되고 원인 addLinkedItems인 revision이 하나 늘며 빈 화면 대신 그 타일이 보인다

  # ── 추가와 끌어다 놓기 ──────────────────────────────────

  @A04
  Scenario: 아이콘 보기에서 추가하면 선택과 상관없이 지금 위치의 끝에 들어간다
    Given 아이콘 보기의 현재 위치가 Wing "개발"이고 Wing "하위" 타일을 선택했다
    When "Wing 추가…"로 "문서"를 만든다
    Then "문서"는 Wing "개발"의 끝(정렬 순서 2)에 있고 원인 addGroup인 revision 하나가 늘었다
    And 지금 화면에 "문서" 타일이 보인다

  @A04
  Scenario Outline: 타일 위나 빈 곳에 놓으면 그에 따라 옮긴다
    Given 아이콘 보기의 현재 위치가 최상위다
    When <항목>을 <놓은 곳>에 끌어다 놓는다
    Then <결과>

    Examples:
      | 항목                    | 놓은 곳                     | 결과                                                         |
      | 웹 링크 "API 명세"        | Wing "개발" 타일              | "API 명세"는 Wing "개발"의 끝에 있고 원인 move인 revision이 하나 는다   |
      | Bishop 파일 "README.md"  | Bishop "README.md" 자신       | 드롭이 받아들여지지 않고 revision이 생기지 않는다                   |
      | 웹 링크 "API 명세"        | Bishop 파일 "README.md" 타일   | 드롭이 받아들여지지 않고 revision이 생기지 않는다                   |
      | Wing "개발"의 "backend"   | 최상위 격자의 빈 곳             | "backend"는 최상위의 끝에 있고 원인 move인 revision이 하나 는다       |

  Scenario Outline: Finder에서 끌어온 파일은 Wing 타일이나 빈 곳에 놓으면 연결한다
    Given 아이콘 보기의 현재 위치가 Wing "개발"이다
    When Finder에서 실제 파일 하나를 <놓은 곳>에 놓는다
    Then <결과>

    Examples:
      | 놓은 곳              | 결과                                                           |
      | Wing "하위" 타일      | Wing "하위"의 끝에 Bishop이 추가되고 원인 addLinkedItems인 revision이 하나 는다 |
      | 격자의 빈 곳           | Wing "개발"의 끝에 Bishop이 추가되고 revision이 하나 는다                  |
      | Bishop "backend" 타일 | 드롭이 받아들여지지 않는다                                            |

  # ── 선택과 키보드 ───────────────────────────────────────

  Scenario Outline: 방향키는 격자 안에서 선택을 옮긴다
    Given 최상위에 항목 7개가 있고 격자가 한 줄에 3개씩 보이며 <처음> 번째 타일을 선택했다
    When <키>를 누른다
    Then <다음> 번째 타일이 선택된다

    Examples:
      | 처음 | 키  | 다음 |
      | 1   | →  | 2   |
      | 3   | →  | 3   |
      | 2   | ↓  | 5   |
      | 6   | ↓  | 6   |
      | 5   | ↑  | 2   |
      | 1   | ←  | 1   |
      | 7   | ↑  | 4   |

  Scenario: 아이콘 보기에서도 편집 명령은 목록 보기와 같다
    Given 아이콘 보기의 현재 위치가 최상위이고 Bishop 파일 "README.md"를 선택했다
    When "위로 이동"(⌥⌘↑)을 실행한다
    Then 타일 순서는 "README.md", "개발", "API 명세"이고 원인 move인 revision 하나가 늘었다
    And "README.md"는 계속 선택돼 있다

  # ── 연결 상태와 기호 ────────────────────────────────────

  Scenario: 타일은 연결 상태를 기호와 문구로 함께 보인다
    Given "README.md"의 실제 파일이 삭제됐고 상태가 "대상 없음"으로 확인됐다
    When 아이콘 보기로 최상위를 본다
    Then "README.md" 타일에 "대상 없음" 상태 기호와 문구가 있고 접근성 라벨에 "대상 없음"이 들어 있다

  Scenario Outline: Bishop 아이콘 설정은 디스크 접근 없이 기호를 정한다
    Given 설정의 "Bishop 아이콘"이 <설정>이다
    When 목록 보기와 아이콘 보기에서 <항목>의 기호를 정한다
    Then 기호는 <기호>이고 대상 파일에는 접근하지 않으며 revision 수는 그대로다

    Examples:
      | 설정          | 항목                  | 기호                                    |
      | 기호(기본)     | Bishop 파일 "README.md" | Bishop 심볼                            |
      | 기호(기본)     | Bishop 폴더 "backend"   | Bishop 폴더 심볼                        |
      | 파일 종류 아이콘 | Bishop 파일 "설계.key"   | 확장자 key의 일반 파일 종류 아이콘 + Bishop 배지 |
      | 파일 종류 아이콘 | Bishop 폴더 "backend"   | 일반 폴더 아이콘 + Bishop 배지             |
      | 파일 종류 아이콘 | Wing "개발"             | folder(설정과 무관)                     |

  # ── 보관된 Board ────────────────────────────────────────

  Scenario: 보관된 Board에서는 아이콘 보기로 탐색·열기만 하고 편집은 막는다
    Given Board "서비스 A"가 보관돼 있고 아이콘 보기다
    When Wing "개발"에 들어갔다가 위로 나오고, "README.md"를 이중 클릭하고, "API 명세"를 Wing "개발" 타일에 끌어다 놓는다
    Then 탐색과 열기는 되고 드롭은 받아들여지지 않으며 revision 수는 그대로다

  # ── 명령과 문구 ─────────────────────────────────────────

  Scenario: 보기 명령이 메뉴와 툴바에 있다
    When 앱 메뉴와 툴바를 확인한다
    Then 보기 메뉴에 "아이콘으로 보기"(⌘1), "목록으로 보기"(⌘2), "들어가기"(⌘↓), "상위 Wing으로"(⌘↑), "뒤로"(⌘[)가 있다
    And 툴바에 아이콘·목록 전환 세그먼트가 있고, 설정 창에 "Bishop 아이콘" 선택이 있다
    And String Catalog에 위 메뉴 문구, "Wing이 비어 있습니다", "항목 %lld개" 문구가 있다
