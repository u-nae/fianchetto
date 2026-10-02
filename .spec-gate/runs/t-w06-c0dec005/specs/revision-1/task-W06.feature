@task-W06
Feature: W06 읽기 전용 보안 범위 북마크 어댑터
  Platform 어댑터는 사용자가 고른 파일·폴더 URL에서 읽기 전용 보안 범위 북마크를 만들고(0001), 나중에 해석해 접근한다.
  어댑터는 대상 파일의 내용·위치·속성을 바꾸지 않는다. 북마크 갱신은 북마크 바이트만 새로 돌려주며 구성 이력과 무관하다(불변식 8).
  해석 실패 원인은 결정표 bookmark_failure_cause(W06.decision.yaml)로 분류한다. 원인을 화면 상태로 보여 주는 일은 W15가 한다.
  돌려주는 경로는 "."·".."를 정리한 절대 경로이며 심볼릭 링크는 풀지 않는다(사용자가 고른 표기를 기록한다).
  파일 시스템 식별자는 심볼릭 링크를 푼 실제 대상에서 구하며, 북마크 생성 결과에 넣지 않는다(확정 시점에만 구한다, 0004).
  "시스템 어댑터"는 Foundation 북마크·리소스 값 호출을 감싼 얇은 계층이고, 일부 시나리오는 이를 가짜로 바꿔 OS 동작을 재현한다.
  모든 시나리오는 테스트마다 만든 임시 디렉토리의 파일·폴더를 쓰고 끝나면 지운다.

  # ── 생성 ───────────────────────────────────────────────

  @A02
  Scenario Outline: 고른 대상에서 북마크를 만들면 종류와 경로를 함께 돌려준다
    Given 임시 디렉토리에 <대상>이 있다
    When 그 URL로 북마크를 만든다
    Then 북마크 바이트, 대상 종류 <종류>, "."·".."를 정리한 절대 경로가 돌아온다

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

  @A02
  Scenario: 만든 북마크를 해석하면 같은 대상을 가리킨다
    Given 파일 "design.md"의 북마크가 있다
    When 북마크를 해석한다
    Then 해석 결과는 "design.md"의 경로이고 갱신할 북마크는 없다

  @A02
  Scenario: 대상이 같은 볼륨 안에서 이동해도 해석은 새 위치를 가리키고 갱신 북마크를 준다
    Given 파일 "design.md"의 북마크가 있다
    When 파일을 같은 볼륨의 하위 폴더 "archive"로 옮긴 뒤 북마크를 해석한다
    Then 해석 결과는 "archive/design.md"의 경로다
    And 해석 결과에는 새 위치로 만든 갱신 북마크가 있고, 그 북마크를 해석하면 갱신이 필요 없다

  Scenario: 경로가 그대로여도 시스템이 stale을 알리면 갱신 북마크를 만든다
    Given 시스템 어댑터가 파일 "design.md"의 북마크를 같은 경로로 해석하면서 stale을 알린다
    When 북마크를 해석한다
    Then 해석 결과는 "design.md"의 경로이고 갱신 북마크가 있다

  Scenario: 갱신 북마크를 만들지 못해도 해석은 성공하고 갱신 실패를 알린다
    Given 시스템 어댑터가 파일 "design.md"의 북마크를 stale로 해석하고, 새 북마크 생성은 실패한다
    When 북마크를 해석한다
    Then 해석 결과는 "design.md"의 경로이고 갱신 북마크는 없으며 "갱신 실패" 표시가 있다

  Scenario: 대상이 삭제되면 해석은 대상 없음으로 실패한다
    Given 파일 "design.md"의 북마크가 있다
    When 파일을 지운 뒤 북마크를 해석한다
    Then 해석은 원인 missing으로 실패한다

  Scenario: 손상된 북마크 바이트는 확인 실패로 분류한다
    When 임의 바이트를 북마크로 해석한다
    Then 해석은 원인 check_failed로 실패한다

  Scenario Outline: 시스템 오류를 오류 범주로 바꾼다
    Given 해석이 오류 도메인 <도메인>, 코드 <코드>로 실패한다
    When 오류 범주를 구한다
    Then error_kind는 <error_kind>이다

    Examples:
      | 도메인            | 코드                        | error_kind    |
      | NSCocoaErrorDomain | NSFileNoSuchFileError        | no_such_file  |
      | NSCocoaErrorDomain | NSFileReadNoSuchFileError    | no_such_file  |
      | NSCocoaErrorDomain | NSFileReadNoPermissionError  | no_permission |
      | NSPOSIXErrorDomain | ENOENT                       | no_such_file  |
      | NSPOSIXErrorDomain | EACCES                       | no_permission |
      | NSPOSIXErrorDomain | EPERM                        | no_permission |
      | NSCocoaErrorDomain | NSFileReadCorruptFileError   | other         |
      | NSURLErrorDomain   | -1                           | other         |

  Scenario Outline: 북마크가 기록한 볼륨 경로로 볼륨 상태를 정한다
    Given 시스템 어댑터가 북마크의 볼륨 경로로 <볼륨 경로>를 돌려준다
    When 볼륨 상태를 구한다
    Then volume_state는 <volume_state>이다

    Examples:
      | 볼륨 경로                         | volume_state |
      | 존재하는 디렉토리                 | mounted      |
      | 존재하지 않는 "/Volumes/분리됨"   | unmounted    |
      | 읽을 수 없음(오류)                | unknown      |

  Scenario Outline: 실제 해석 실패는 오류와 볼륨 상태를 함께 써서 원인을 정한다
    Given 시스템 어댑터의 해석이 <오류>로 실패하고 북마크의 볼륨 경로는 <볼륨 경로>이다
    When 북마크를 해석한다
    Then 해석은 원인 <cause>로 실패한다

    Examples:
      | 오류              | 볼륨 경로                       | cause              |
      | 파일 없음         | 존재하지 않는 "/Volumes/분리됨" | volume_unavailable |
      | 파일 없음         | 존재하는 디렉토리               | missing            |
      | 파일 없음         | 읽을 수 없음(오류)              | check_failed       |
      | 읽기 권한 없음    | 존재하는 디렉토리               | access_denied      |

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
    Then 작업은 접근 시작 결과와 상관없이 한 번 실행된다
    And 접근 종료 호출 수는 <종료 호출>이다
    And 작업의 결과나 오류가 그대로 호출자에게 전달된다

    Examples:
      | 시작 결과 | 작업              | 종료 호출 |
      | 성공      | 값을 돌려주는 작업 | 1         |
      | 성공      | 오류를 던지는 작업 | 1         |
      | 실패      | 값을 돌려주는 작업 | 0         |
      | 실패      | 오류를 던지는 작업 | 0         |

  # ── 파일 시스템 식별자 (0004) ────────────────────────────

  Scenario: 같은 대상의 식별자는 같고, 다른 대상의 식별자는 다르다
    Given 파일 "a.md"와 "b.md"가 있다
    And 폴더 "linked"는 임시 디렉토리를 가리키는 심볼릭 링크다
    When "a.md", "b.md", "linked/a.md"와 "./sub/../a.md" 표기의 식별자를 구한다
    Then "a.md"와 "linked/a.md", "./sub/../a.md"의 파일 식별자·볼륨 식별자는 모두 같다
    And "a.md"와 "b.md"의 파일 식별자는 다르고 볼륨 식별자는 같다

  Scenario: 같은 볼륨 안에서 이동·이름 변경한 대상은 같은 파일 식별자를 가진다
    Given 파일 "a.md"의 식별자를 구해 둔다
    When 파일을 "renamed.md"로 바꾼 뒤 식별자를 구한다
    Then 두 식별자로 같은 대상 판정(0004)을 하면 same_target이다

  Scenario: 없는 대상의 식별자는 얻을 수 없다
    When 존재하지 않는 경로의 식별자를 구한다
    Then 파일 식별자와 볼륨 식별자가 모두 없다

  # ── 원본 보존 ───────────────────────────────────────────

  @A02
  Scenario: 북마크 생성·해석·접근·식별자 조회는 대상을 바꾸지 않는다
    Given 파일 "design.md"의 내용·수정 시각·권한과 폴더 "assets"의 목록을 기억한다
    When 두 대상의 북마크를 만들고, 해석하고, 접근 범위 안에서 존재를 확인하고, 식별자를 구한다
    Then 파일의 내용·수정 시각·권한과 폴더 목록은 처음과 같다
