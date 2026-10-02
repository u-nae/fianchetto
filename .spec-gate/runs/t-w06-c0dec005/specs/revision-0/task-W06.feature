@task-W06
Feature: W06 읽기 전용 보안 범위 북마크 어댑터
  Platform 어댑터는 사용자가 고른 파일·폴더 URL에서 읽기 전용 보안 범위 북마크를 만들고(0001), 나중에 해석해 접근한다.
  어댑터는 대상 파일의 내용·위치·속성을 바꾸지 않는다. 북마크 갱신은 북마크 바이트만 새로 돌려주며 구성 이력과 무관하다(불변식 8).
  해석 실패 원인은 결정표 bookmark_failure_cause(W06.decision.yaml)로 분류한다.
  모든 시나리오는 테스트마다 만든 임시 디렉토리의 파일·폴더를 쓰고 끝나면 지운다.

  # ── 생성 ───────────────────────────────────────────────

  Scenario Outline: 고른 대상에서 북마크를 만들면 종류와 경로를 함께 돌려준다
    Given 임시 디렉토리에 <대상>이 있다
    When 그 URL로 북마크를 만든다
    Then 북마크 바이트, 대상 종류 <종류>, 표준화된 절대 경로, 파일 시스템 식별자가 돌아온다

    Examples:
      | 대상                         | 종류   |
      | 파일 "design.md"             | file   |
      | 폴더 "assets"                | folder |
      | 패키지 폴더 "Deck.key"        | file   |

  Scenario: 북마크는 보안 범위와 읽기 전용 옵션으로 만든다
    Given 북마크 생성 호출을 기록하는 시스템 어댑터로 북마크 어댑터를 만든다
    When 파일 하나의 북마크를 만든다
    Then 생성 옵션은 보안 범위와 읽기 전용 보안 범위를 모두 포함한다
    And 해석 옵션은 보안 범위를 포함한다

  Scenario: 없는 대상의 북마크는 만들 수 없다
    When 존재하지 않는 경로의 북마크를 만든다
    Then "북마크를 만들 수 없음" 오류가 난다

  # ── 해석 ───────────────────────────────────────────────

  Scenario: 만든 북마크를 해석하면 같은 대상을 가리킨다
    Given 파일 "design.md"의 북마크가 있다
    When 북마크를 해석한다
    Then 해석 결과는 "design.md"의 경로이고 갱신할 북마크는 없다

  Scenario: 대상이 같은 볼륨 안에서 이동해도 해석은 새 위치를 가리키고 갱신 북마크를 준다
    Given 파일 "design.md"의 북마크가 있다
    When 파일을 같은 볼륨의 하위 폴더 "archive"로 옮긴 뒤 북마크를 해석한다
    Then 해석 결과는 "archive/design.md"의 경로다
    And 해석 결과에는 새 위치로 만든 갱신 북마크가 있고, 그 북마크를 해석하면 갱신이 필요 없다

  Scenario: 대상이 삭제되면 해석은 대상 없음으로 실패한다
    Given 파일 "design.md"의 북마크가 있다
    When 파일을 지운 뒤 북마크를 해석한다
    Then 해석은 원인 missing으로 실패한다

  Scenario: 손상된 북마크 바이트는 확인 실패로 분류한다
    When 임의 바이트를 북마크로 해석한다
    Then 해석은 원인 check_failed로 실패한다

  Scenario Outline: 해석 실패 원인을 볼륨 상태와 오류 범주로 분류한다
    Given volume_state가 <volume_state>이고 error_kind가 <error_kind>이다
    When 실패 원인을 분류한다
    Then cause는 <cause>이다

    Examples:
      | volume_state | error_kind    | cause              |
      | unmounted    | no_such_file  | volume_unavailable |
      | unmounted    | no_permission | volume_unavailable |
      | unmounted    | other         | volume_unavailable |
      | mounted      | no_permission | access_denied      |
      | unknown      | no_permission | access_denied      |
      | mounted      | no_such_file  | missing            |
      | unknown      | no_such_file  | check_failed       |
      | mounted      | other         | check_failed       |
      | unknown      | other         | check_failed       |

  # ── 접근 범위 ───────────────────────────────────────────

  Scenario Outline: 보안 범위 접근은 시작한 경우에만 정확히 한 번 끝낸다
    Given 접근 시작 결과가 <시작 결과>인 대상이 있다
    When 그 대상에 대해 <작업>을 접근 범위 안에서 실행한다
    Then 접근 종료 호출 수는 <종료 호출>이다
    And 작업의 결과나 오류가 그대로 호출자에게 전달된다

    Examples:
      | 시작 결과 | 작업              | 종료 호출 |
      | 성공      | 값을 돌려주는 작업 | 1         |
      | 성공      | 오류를 던지는 작업 | 1         |
      | 실패      | 값을 돌려주는 작업 | 0         |

  # ── 파일 시스템 식별자 (0004) ────────────────────────────

  Scenario: 같은 대상의 식별자는 같고, 다른 대상의 식별자는 다르다
    Given 파일 "a.md"와 "b.md"가 있다
    When 각 파일과 "a.md"의 다른 경로 표기(심볼릭 링크를 거친 경로)의 식별자를 구한다
    Then "a.md"와 다른 경로 표기의 파일 식별자·볼륨 식별자는 같다
    And "a.md"와 "b.md"의 파일 식별자는 다르고 볼륨 식별자는 같다

  Scenario: 같은 볼륨 안에서 이동·이름 변경한 대상은 같은 파일 식별자를 가진다
    Given 파일 "a.md"의 식별자를 구해 둔다
    When 파일을 "renamed.md"로 바꾼 뒤 식별자를 구한다
    Then 두 식별자로 같은 대상 판정(0004)을 하면 same_target이다

  Scenario: 없는 대상의 식별자는 얻을 수 없다
    When 존재하지 않는 경로의 식별자를 구한다
    Then 파일 식별자와 볼륨 식별자가 모두 없다

  # ── 원본 보존 ───────────────────────────────────────────

  Scenario: 북마크 생성·해석·접근·식별자 조회는 대상을 바꾸지 않는다
    Given 파일 "design.md"의 내용·수정 시각·권한과 폴더 "assets"의 목록을 기억한다
    When 두 대상의 북마크를 만들고, 해석하고, 접근 범위 안에서 존재를 확인하고, 식별자를 구한다
    Then 파일의 내용·수정 시각·권한과 폴더 목록은 처음과 같다
