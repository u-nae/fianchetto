@task-W02
Feature: W02 구성 스냅샷 값 타입과 트리 규칙
  Revision에 담기는 구성 스냅샷은 프로젝트 이름과 전체 Node 구성을 값으로 보존한다.
  스냅샷 검증은 트리 규칙을 어긴 구성을 거부하고, 위반한 Node와 위반 종류를 알려 준다.
  Node 종류별 필드와 부모 자격은 결정표 node_shape_validity(W02.decision.yaml)를 따른다.

  Background:
    Given 프로젝트 이름이 "서비스 A"인 구성 스냅샷이 있다

  # ── 직렬화 ───────────────────────────────────────────────

  Scenario: 유효한 스냅샷은 JSON으로 기록한 뒤 다시 읽어도 같은 구성이다
    Given 스냅샷에 다음 Node가 있다
      | 표시 이름   | 종류    | 부모 | 정렬 순서 | 기록 당시 경로     | URL                         |
      | 개발        | group   |      | 0         |                    |                             |
      | backend     | folder  | 개발 | 0         | /dev/legacy-api    |                             |
      | 설계 메모   | file    | 개발 | 1         | /docs/design.md    |                             |
      | API 명세    | webLink |      | 1         |                    | https://example.com/api     |
    When 스냅샷을 JSON으로 기록하고 다시 읽는다
    Then 읽은 스냅샷은 원래 스냅샷과 같다
    And 각 Node의 UUID, 표시 이름, 부모, 정렬 순서, referenceID, 기록 당시 경로, URL이 보존된다

  Scenario: 기록한 JSON에는 스냅샷 schema version 1이 담긴다
    When 스냅샷을 JSON으로 기록한다
    Then JSON의 schema version은 1이다

  Scenario Outline: 지원하지 않는 schema version의 JSON은 읽지 않는다
    Given schema version이 <version>인 스냅샷 JSON이 있다
    When 그 JSON을 읽는다
    Then "지원하지 않는 schema version" 오류로 거부된다

    Examples:
      | version |
      | 0       |
      | 2       |
      | 없음    |

  Scenario: 손상된 JSON은 읽지 않는다
    Given 중간에서 잘린 스냅샷 JSON이 있다
    When 그 JSON을 읽는다
    Then 읽기 오류로 거부되고 스냅샷이 만들어지지 않는다

  Scenario: Node 목록의 저장 순서가 달라도 같은 구성은 같은 스냅샷이다
    Given 같은 Node들을 서로 다른 목록 순서로 담은 두 스냅샷이 있다
    When 두 스냅샷을 비교한다
    Then 두 스냅샷은 같다

  Scenario: 스냅샷을 복사해 바꿔도 원래 스냅샷은 바뀌지 않는다
    Given 스냅샷에 표시 이름이 "backend"인 Node가 있다
    When 스냅샷을 복사하고 복사본에서 그 Node의 표시 이름을 "api"로 바꾼다
    Then 원래 스냅샷의 그 Node 표시 이름은 "backend"이다

  # ── 이름 ─────────────────────────────────────────────────

  # 입력 칸은 공백을 보존하려고 Swift 문자열 리터럴로 적는다(\n 줄바꿈, \t 탭, \u{3000} 전각 공백).
  # Gherkin 표에서 \n은 줄바꿈으로 해석되므로 표 안에서는 \\n으로 적는다.
  Scenario Outline: 표시 이름은 앞뒤 공백을 정리해 만든다
    When 입력 <입력>으로 표시 이름을 만든다
    Then 표시 이름은 <결과>이다

    Examples:
      | 입력                              | 결과                  |
      | "backend"                         | "backend"             |
      | "  backend"                       | "backend"             |
      | "backend\\n"                      | "backend"             |
      | "\t인증 리팩토링 1차\u{3000}"      | "인증 리팩토링 1차"   |
      | "서비스  A"                       | "서비스  A"           |

  Scenario Outline: 공백만 있거나 비어 있는 표시 이름은 만들 수 없다
    When 입력 <입력>으로 표시 이름을 만든다
    Then "빈 이름" 오류로 거부된다

    Examples:
      | 입력         |
      | ""           |
      | "   "        |
      | "\\n\t"      |
      | "\u{3000}"   |

  Scenario: 프로젝트 이름에도 표시 이름 규칙을 적용한다
    When 입력 "  서비스 A  "로 프로젝트 이름을 만든다
    Then 프로젝트 이름은 "서비스 A"이다
    And 입력 "   "로 프로젝트 이름을 만들면 "빈 이름" 오류로 거부된다

  Scenario: 정리되지 않은 이름을 담은 JSON은 검증에서 거부한다
    Given 표시 이름이 " backend"인 Node를 담은 스냅샷 JSON이 있다
    When 그 JSON을 읽어 검증한다
    Then 스냅샷은 거부되고 그 Node에 "빈 이름 또는 정리되지 않은 이름" 위반이 보고된다

  Scenario: 같은 부모 아래 같은 표시 이름과 같은 경로의 Node를 병합하지 않는다
    Given 그룹 "개발" 아래 표시 이름이 "backend"이고 기록 당시 경로가 "/dev/legacy-api"인 연결 폴더 두 개가 서로 다른 UUID로 있다
    When 스냅샷을 검증하고 JSON으로 기록한 뒤 다시 읽는다
    Then 스냅샷은 유효하다
    And 두 Node는 각자의 UUID로 모두 남아 있다

  # ── 트리 구조 ───────────────────────────────────────────

  Scenario: Node가 없는 빈 구성도 유효하다
    Given 스냅샷에 Node가 없다
    When 스냅샷을 검증한다
    Then 스냅샷은 유효하다

  @A14
  Scenario: 자기 자신을 부모로 가진 그룹은 순환으로 거부한다
    Given 그룹 "개발"의 부모가 "개발" 자신이다
    When 스냅샷을 검증한다
    Then 스냅샷은 거부되고 "개발"에 "순환" 위반이 보고된다

  @A14
  Scenario: 두 그룹이 서로의 부모인 구성은 순환으로 거부한다
    Given 그룹 "A"의 부모가 "B"이고 그룹 "B"의 부모가 "A"이다
    When 스냅샷을 검증한다
    Then 스냅샷은 거부되고 "A"와 "B"에 "순환" 위반이 보고된다

  @A14
  Scenario: 깊은 자손을 거쳐 돌아오는 순환도 거부한다
    Given 그룹 "G1"부터 "G5"까지 G1 ← G2 ← G3 ← G4 ← G5 순서로 중첩되어 있다
    And 그룹 "G1"의 부모가 "G5"이다
    When 스냅샷을 검증한다
    Then 스냅샷은 거부되고 G1~G5 모두에 "순환" 위반이 보고된다

  Scenario: 존재하지 않는 부모를 가리키는 Node는 거부한다
    Given 연결 파일 "설계 메모"의 부모 ID가 스냅샷에 없는 UUID다
    When 스냅샷을 검증한다
    Then 스냅샷은 거부되고 "설계 메모"에 "부모 없음" 위반이 보고된다

  Scenario: 같은 UUID의 Node가 두 번 나오면 거부한다
    Given 서로 다른 부모 아래 같은 UUID를 가진 Node 두 개가 있다
    When 스냅샷을 검증한다
    Then 스냅샷은 거부되고 그 UUID에 "중복 Node" 위반이 보고된다

  Scenario Outline: Node의 부모는 그룹이거나 프로젝트 최상위여야 한다
    Given 종류가 <parent_kind>인 Node 아래에 연결 파일 "notes.md"가 있다
    When 스냅샷을 검증한다
    Then "notes.md"의 verdict는 <verdict>이고 violation은 <violation>이다

    Examples:
      | parent_kind | verdict | violation        |
      | root        | valid   | none             |
      | group       | valid   | none             |
      | folder      | invalid | parent_not_group |
      | file        | invalid | parent_not_group |
      | webLink     | invalid | parent_not_group |

  Scenario Outline: Node 종류별 필드 모양을 결정표대로 검증한다
    Given node_kind가 <node_kind>이고 reference_fields가 <reference_fields>이고 url이 <url>인 Node가 최상위(parent_kind root)에 있다
    When 스냅샷을 검증한다
    Then 그 Node의 verdict는 <verdict>이고 violation은 <violation>이다

    Examples:
      | node_kind | reference_fields | url                      | verdict | violation            |
      | group   | none       | absent                   | valid   | none                 |
      | group   | complete   | absent                   | invalid | unexpected_reference |
      | group   | none       | https://example.com      | invalid | unexpected_url       |
      | folder  | complete   | absent                   | valid   | none                 |
      | folder  | none       | absent                   | invalid | missing_reference    |
      | file    | incomplete | absent                   | invalid | incomplete_reference |
      | file    | complete   | https://example.com      | invalid | unexpected_url       |
      | webLink | none       | https://example.com/api  | valid   | none                 |
      | webLink | none       | HTTP://Example.com       | valid   | none                 |
      | webLink | none       | absent                   | invalid | missing_url          |
      | webLink | none       | ftp://example.com        | invalid | invalid_url          |
      | webLink | none       | example.com              | invalid | invalid_url          |
      | webLink | none       | https:///path            | invalid | invalid_url          |
      | webLink | complete   | https://example.com      | invalid | unexpected_reference |

  Scenario Outline: 기록 당시 경로가 절대 경로가 아니면 참조 필드가 불완전하다
    Given 연결 폴더 "backend"의 referenceID가 있고 기록 당시 경로가 "<경로>"이다
    When 스냅샷을 검증한다
    Then "backend"의 verdict는 invalid이고 violation은 incomplete_reference이다

    Examples:
      | 경로            |
      |                 |
      | dev/legacy-api  |

  # ── 정렬 순서 ───────────────────────────────────────────

  Scenario: 형제의 정렬 순서는 부모마다 0부터 빈틈없이 매긴다
    Given 그룹 "개발" 아래 Node 정렬 순서가 0, 1, 2이고 최상위 Node 정렬 순서가 0, 1이다
    When 스냅샷을 검증한다
    Then 스냅샷은 유효하다

  Scenario Outline: 형제 정렬 순서에 중복·빈칸·음수가 있으면 거부한다
    Given 그룹 "개발" 아래 Node 정렬 순서가 <순서>이다
    When 스냅샷을 검증한다
    Then 스냅샷은 거부되고 그룹 "개발"의 하위 항목에 "정렬 순서" 위반이 보고된다

    Examples:
      | 순서     |
      | 0, 0, 1  |
      | 0, 2     |
      | 1, 2     |
      | -1, 0    |

  # ── 보고 ─────────────────────────────────────────────────

  Scenario: 여러 Node가 규칙을 어기면 위반을 모두 보고한다
    Given 연결 폴더 "backend" 아래에 연결 파일 "notes.md"가 있다
    And 웹 링크 "API 명세"의 URL이 "ftp://example.com"이다
    When 스냅샷을 검증한다
    Then 스냅샷은 거부된다
    And "notes.md"에 parent_not_group 위반, "API 명세"에 invalid_url 위반이 함께 보고된다
