@task-W17
Feature: W17 이력 목록과 날짜 시점 조회
  Board의 revision 목록을 인스펙터의 '항목 | 이력' 중 이력 탭에서 순번 역순(최신이 위)으로 보여 주고, 날짜·시각으로 그 시점의 마지막 기록을 찾는다(PRD §6-D, 0019, DESIGN.md 16.1·16.2).
  목록은 필요한 만큼만 불러오고 고른 revision만 디코딩한다(PRD §8 경량화). 저장은 절대 시각, 표시·선택은 시스템 시간대다.
  목록 순서는 순번이 기준이다. 조회는 현재 구성을 바꾸지 않고 revision을 만들지 않는다(PRD §7).
  과거 구성을 가운데 영역에 그리는 일(과거 구성 띠, 읽기 전용, 고른 항목 카드)은 W18 범위다.

  Background:
    Given 시스템 시간대가 Asia/Seoul이고 화면 언어가 한국어다
    And Board "서비스 A"가 있다

  # ── 날짜 시점 조회(순수 규칙) ─────────────────────────────

  @A05
  Scenario Outline: 고른 시각 이하의 기록 중 가장 늦은 시각의 기록을 고른다
    Given "서비스 A"의 revision이 다음과 같다
      | 순번 | 기록 시각                 |
      | 1   | 2026-10-01 09:00:00     |
      | 2   | 2026-10-02 14:20:30     |
      | 3   | 2026-10-03 08:00:00     |
    When <고른 시각>으로 찾는다
    Then 순번 <결과> revision을 고른다

    Examples:
      | 고른 시각               | 결과 |
      | 2026-10-01 09:00:00   | 1   |
      | 2026-10-02 14:20:29   | 1   |
      | 2026-10-02 14:20:30   | 2   |
      | 2026-10-02 23:59:59   | 2   |
      | 2026-10-05 00:00:00   | 3   |

  Scenario: 시계가 뒤로 간 기록이 있으면 순번이 아니라 기록 시각으로 고른다
    Given "서비스 A"의 revision이 다음과 같다
      | 순번 | 기록 시각                 |
      | 1   | 2026-10-01 09:00:00     |
      | 2   | 2026-10-03 10:00:00     |
      | 3   | 2026-10-02 12:00:00     |
    When 2026-10-02 13:00:00으로 찾는다
    Then 순번 3 revision을 고른다
    When 2026-10-03 10:00:00으로 찾는다
    Then 순번 2 revision을 고른다

  Scenario: 같은 기록 시각이 여럿이면 순번이 큰 기록을 고른다
    Given "서비스 A"의 revision이 다음과 같다
      | 순번 | 기록 시각                 |
      | 1   | 2026-10-01 09:00:00     |
      | 2   | 2026-10-01 09:00:00     |
      | 3   | 2026-10-01 08:59:00     |
    When 2026-10-01 09:00:00으로 찾는다
    Then 순번 2 revision을 고른다

  @A05
  Scenario: Board가 생기기 전 시각이면 기록 없음이고 선택을 바꾸지 않는다
    Given "서비스 A"의 첫 revision 기록 시각이 2026-10-01 09:00:00이다
    And 이력 탭에서 순번 1 revision을 골라 두었다
    When 이력 탭의 '날짜로 찾기'에서 2026-09-30 23:59:59로 찾는다
    Then 날짜 칸 아래에 "이 시점의 기록 없음"이 보인다
    And 선택은 순번 1 revision 그대로다

  @A05
  Scenario: 찾은 기록은 목록에서 골라지고 실제 기록 시각이 보인다
    Given "서비스 A"의 revision 120개가 순번 1부터 하루 간격으로 기록되어 있고 이력 탭은 처음 불러온 만큼만 보여 준다
    When 이력 탭의 '날짜로 찾기'에서 순번 3의 기록 시각으로 찾는다
    Then 순번 3 revision 행이 목록에 있고 골라진 상태이며 화면에 보인다
    And 그 행의 아래 줄은 "#3 · " 다음에 순번 3의 실제 기록 시각(시스템 시간대)이다

  Scenario: 날짜로 찾는 시각의 분 경계는 사용자 결정(Q-W17-1)을 따른다
    Given "서비스 A"에 순번 2 revision이 2026-10-02 14:20:30에 기록되어 있고 그 앞 기록은 2026-10-02 14:19:00이다
    When '날짜로 찾기'에서 날짜 2026-10-02, 시각 오후 2:20을 고른다
    Then 고르는 revision은 Q-W17-1 답에 따른다

  # ── 목록 불러오기와 디코딩 ─────────────────────────────

  Scenario: 이력 탭은 순번 역순으로 첫 묶음만 불러온다
    Given "서비스 A"의 revision이 120개다
    When 이력 탭을 연다
    Then 목록 첫 행은 순번 120이고 순번이 하나씩 줄어든다
    And 불러온 revision 행은 한 묶음(50개)이다

  Scenario: 목록 끝에 닿으면 다음 묶음을 더 불러온다
    Given "서비스 A"의 revision이 120개이고 이력 탭이 첫 묶음을 보여 준다
    When 불러온 마지막 행이 보이게 된다
    Then 불러온 revision 행은 100개가 되고 마지막 행은 순번 21이다
    When 다시 불러온 마지막 행이 보이게 된다
    Then 불러온 revision 행은 120개가 되고 마지막 행은 순번 1이며 더 불러오지 않는다

  Scenario: 목록은 스냅샷을 디코딩하지 않고 고른 revision만 디코딩한다
    Given "서비스 A"의 순번 2 revision 스냅샷이 손상되어 있다
    When 이력 탭을 연다
    Then 순번 2 행을 포함한 목록이 정상으로 보인다
    When 순번 3 revision을 고른다
    Then 순번 3 구성이 고른 revision의 구성으로 준비된다
    When 순번 2 revision을 고른다
    Then "이 기록을 읽을 수 없습니다" 안내가 보이고 선택은 순번 3 그대로다

  Scenario: 목록 정보를 읽지 못하면 이력 탭에 오류를 보이고 현재 구성은 그대로다
    Given "서비스 A"의 revision 하나의 원인 기록이 손상되어 목록 정보를 읽을 수 없다
    When 이력 탭을 연다
    Then 이력 탭에 "기록을 불러오지 못했습니다"가 보인다
    And 가운데 영역의 현재 구성과 편집 동작은 그대로다

  # ── 행 표시 ─────────────────────────────────────────

  Scenario Outline: revision 행은 원인 문구와 기호를 보인다
    Given "서비스 A"에 원인이 <원인>인 revision이 있다
    When 이력 탭을 연다
    Then 그 행의 문구는 "<문구>"이고 기호는 <기호>다

    Examples:
      | 원인             | 문구              | 기호                      |
      | created         | Board 만들기       | plus.square              |
      | renameProject   | Board 이름 변경    | pencil                   |
      | addGroup        | Wing 추가          | plus                     |
      | addLinkedItems  | Bishop 추가        | plus                     |
      | addWebLink      | 웹 링크 추가        | plus                     |
      | renameNode      | 이름 변경           | pencil                   |
      | changeURL       | URL 변경           | pencil                   |
      | move            | 이동               | arrow.up.and.down        |
      | remove          | 제거               | minus                    |
      | replaceTarget   | 연결 대상 변경       | arrow.triangle.swap      |
      | changePurpose   | 아이콘 변경          | pencil                   |
      | duplicated      | 과거 구성에서 만듦    | plus.square.on.square    |
      | imported        | 가져오기            | square.and.arrow.down    |

  Scenario: 복원 revision은 출처 revision의 순번을 문구에 넣는다
    Given "서비스 A"의 순번 7 revision이 순번 4 revision에서 복원한 기록이다
    When 이력 탭을 연다
    Then 순번 7 행의 문구는 "#4에서 복원"이고 기호는 arrow.uturn.backward다

  Scenario: revision 행의 아래 줄과 접근성 라벨은 순번과 실제 기록 시각이다
    Given "서비스 A"의 순번 12 revision이 2026-10-03 14:20에 원인 addGroup으로 기록되었다
    When 이력 탭을 연다
    Then 순번 12 행의 아래 줄은 "#12 · 오후 2:20"이다
    And 순번 12 행의 접근성 라벨은 "Wing 추가, #12, 오후 2:20"이다

  Scenario: 날짜 구역 머리글은 기록이 있는 날에만 만든다
    Given 오늘이 2026-10-03이고 "서비스 A"의 revision이 10월 3일 2개, 10월 1일 1개, 2025년 12월 30일 1개다
    When 이력 탭을 연다
    Then 날짜 구역 머리글은 위에서부터 "오늘 · 10월 3일", "10월 1일", "2025년 12월 30일"이다
    And 기록이 없는 10월 2일 구역은 없다

  Scenario Outline: 날짜 구역 머리글은 결정 history_day_heading을 따른다
    Given 오늘이 <오늘>이다
    When 기록 시각이 <기록 날짜>인 revision의 날짜 구역 머리글을 만든다
    Then is_today는 <is_today>, is_yesterday는 <is_yesterday>, same_year는 <same_year>이고 heading은 "<heading>"이다

    Examples:
      | 오늘          | 기록 날짜       | is_today | is_yesterday | same_year | heading            |
      | 2026-10-03  | 2026-10-03    | true     | false        | true      | 오늘 · 10월 3일      |
      | 2026-10-03  | 2026-10-02    | false    | true         | true      | 어제 · 10월 2일      |
      | 2026-10-03  | 2026-10-01    | false    | false        | true      | 10월 1일            |
      | 2026-10-03  | 2025-12-30    | false    | false        | false     | 2025년 12월 30일     |
      | 2027-01-01  | 2026-12-31    | false    | true         | false     | 어제 · 12월 31일     |
      | 2026-10-03  | 2026-10-05    | false    | false        | true      | 10월 5일            |

  Scenario: 시계가 뒤로 간 기록은 순번 순서를 지키고 날짜 구역을 다시 연다
    Given 오늘이 2026-10-03이고 "서비스 A"의 revision이 순번 1: 10월 2일, 순번 2: 10월 3일, 순번 3: 10월 2일로 기록되었다
    When 이력 탭을 연다
    Then 행 순서는 순번 3, 2, 1이고 머리글은 "어제 · 10월 2일", "오늘 · 10월 3일", "어제 · 10월 2일" 순서로 각 행 위에 있다

  Scenario: '현재 구성' 행은 목록 맨 위에 있고 처음에는 골라져 있다
    When 이력 탭을 연다
    Then '날짜로 찾기' 아래 첫 행은 "현재 구성"이고 골라져 있다
    When 순번 1 revision을 고른 뒤 "현재 구성" 행을 고른다
    Then 고른 revision이 없어진다

  # ── 조회는 기록하지 않는다 ─────────────────────────────

  @A05
  Scenario: 이력 열기·행 고르기·날짜로 찾기는 현재 구성과 revision 수를 바꾸지 않는다
    Given "서비스 A"의 현재 구성이 순번 5 revision이다
    When 이력 탭을 열고 순번 2 revision을 고르고 2026-10-01 09:00:00으로 찾고 "현재 구성" 행을 고른다
    Then "서비스 A"의 revision 수와 현재 revision은 그대로다

  Scenario: 보관된 Board도 이력을 볼 수 있다
    Given "서비스 A"가 보관되어 있다
    When 이력 탭을 열고 순번 1 revision을 고른다
    Then 목록이 보이고 순번 1 revision이 골라진다

  Scenario: 이력 탭이 열린 채 새 revision이 기록되면 목록 맨 위에 더해지고 선택은 유지된다
    Given 이력 탭에서 순번 2 revision을 골라 두었고 현재 revision은 순번 5다
    When 다른 곳에서 "서비스 A"에 Wing 추가가 기록된다
    Then 목록 첫 revision 행은 순번 6 "Wing 추가"이고 선택은 순번 2 그대로다

  Scenario: 다른 Board를 고르면 그 Board의 이력으로 바뀌고 선택은 비워진다
    Given Board "서비스 B"가 있고 이력 탭에서 "서비스 A"의 순번 2 revision을 골라 두었다
    When "서비스 B"를 고른다
    Then 이력 탭은 "서비스 B"의 목록을 보이고 "현재 구성" 행이 골라져 있다

  # ── 여는 곳과 화면 구조 ──────────────────────────────

  Scenario Outline: 이력 보기는 인스펙터를 펴며 이력 탭을 열고, 이력 탭에서 다시 하면 항목 탭으로 돌아간다
    Given 인스펙터가 <인스펙터>이고 탭은 <탭>이다
    When <방법>으로 이력 보기를 실행한다
    Then 인스펙터는 펴져 있고 탭은 <결과 탭>이다

    Examples:
      | 인스펙터 | 탭   | 방법                          | 결과 탭 |
      | 접힘    | 항목 | 보기 메뉴 '이력 보기'(⌘Y)        | 이력   |
      | 펴짐    | 항목 | 툴바 이력 버튼                  | 이력   |
      | 펴짐    | 이력 | 보기 메뉴 '이력 보기'(⌘Y)        | 항목   |

  Scenario: 이력 탭을 열면 Board 사이드바를 접고 닫으면 열기 전 상태로 돌린다
    Given Board 사이드바가 보인다
    When 이력 탭을 연다
    Then Board 사이드바가 접힌다
    When 항목 탭으로 돌아간다
    Then Board 사이드바가 다시 보인다

  Scenario: 사이드바가 이미 접혀 있었으면 이력 탭을 닫아도 접힌 채다
    Given Board 사이드바가 접혀 있다
    When 이력 탭을 열었다가 항목 탭으로 돌아간다
    Then Board 사이드바는 접힌 채다

  Scenario: 고른 Board가 없으면 이력 보기가 꺼져 있다
    Given 고른 Board가 없다
    Then 보기 메뉴 '이력 보기'와 툴바 이력 버튼은 꺼져 있다

  Scenario: 앱을 다시 열면 항목 탭과 현재 구성으로 시작한다
    Given 이력 탭에서 순번 2 revision을 골라 둔 채 앱을 끝냈다
    When 앱을 다시 연다
    Then 인스펙터 탭은 항목이고 고른 revision은 없다

  Scenario: 이력 관련 문구는 String Catalog에 있다
    Then String Catalog에 "이력", "항목", "이력 보기", "날짜로 찾기", "현재 구성", "이 시점의 기록 없음", "이 기록을 읽을 수 없습니다", "기록을 불러오지 못했습니다", "오늘", "어제", "%lld에서 복원" 형태의 복원 문구와 16.2 원인 문구가 있다
