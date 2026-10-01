@task-W03
Feature: W03 구성 편집 연산과 무변경 판정
  확정된 사용자 작업 하나는 구성 스냅샷 하나를 받아 결과 하나를 돌려준다.
  결과는 changed(새 스냅샷), unchanged(입력과 같음), rejected(거부 사유) 중 하나다.
  unchanged와 rejected는 revision을 만들지 않는다(PRD §6-A, §7). 입력 스냅샷은 어떤 경우에도 바뀌지 않는다.
  새 Node UUID와 새 referenceID는 주입된 생성기가 요청 순서대로 내준다.
  거부 사유 어휘: node_not_found, parent_not_group, cycle, blank_name, invalid_url, invalid_position,
  not_web_link, not_linked_item, target_kind_mismatch, invalid_path(절대 경로가 아닌 대상 경로).
  같은 대상 판정은 결정표 target_identity(W03.decision.yaml)를 따른다.

  Background:
    Given 프로젝트 이름이 "서비스 A"인 구성 스냅샷 S가 있다
      | 표시 이름 | 종류    | 부모 | 정렬 순서 | referenceID | 기록 당시 경로  | URL                     |
      | 개발      | group   |      | 0         |             |                 |                         |
      | backend   | folder  | 개발 | 0         | ref-backend | /dev/legacy-api |                         |
      | 설계 메모 | file    | 개발 | 1         | ref-design  | /docs/design.md |                         |
      | API 명세  | webLink |      | 1         |             |                 | https://example.com/api |
    And UUID 생성기는 new-1, new-2, new-3 … 순서로 UUID를 내준다

  Rule: 모든 changed 결과는 W02 스냅샷 검증을 통과하고, 입력 스냅샷 S는 바뀌지 않는다

  # ── 프로젝트 이름 ───────────────────────────────────────

    Scenario: 프로젝트 이름을 바꾸면 이름만 다른 새 스냅샷이 된다
      When 프로젝트 이름을 "  서비스 B "로 바꾼다
      Then 결과는 changed이고 프로젝트 이름은 "서비스 B"이다
      And 모든 Node는 S와 같다

    Scenario: 같은 프로젝트 이름으로 확정하면 무변경이다
      When 프로젝트 이름을 " 서비스 A "로 바꾼다
      Then 결과는 unchanged이다

    Scenario: 빈 프로젝트 이름은 거부한다
      When 프로젝트 이름을 "   "로 바꾼다
      Then 결과는 rejected이고 사유는 blank_name이다

  # ── 그룹 추가 ───────────────────────────────────────────

    Scenario: 위치를 지정하지 않은 그룹은 부모의 마지막에 추가한다
      When 최상위에 그룹 "에셋"을 추가한다
      Then 결과는 changed이고 "에셋"은 UUID new-1, 종류 group, 정렬 순서 2로 최상위에 있다
      And "에셋"에는 referenceID·기록 당시 경로·URL이 없다
      And 기존 Node는 S와 같다

    Scenario: 위치를 지정한 그룹 추가는 뒤쪽 형제의 정렬 순서를 하나씩 민다
      When 그룹 "개발" 아래 정렬 순서 0에 그룹 "공통"을 추가한다
      Then 결과는 changed이고 "개발" 아래 정렬 순서는 "공통" 0, "backend" 1, "설계 메모" 2이다

    Scenario Outline: 그룹 추가를 거부하는 경우
      When <부모> 아래에 그룹 <이름>을 위치 <위치>에 추가한다
      Then 결과는 rejected이고 사유는 <사유>이다

      Examples:
        | 부모                 | 이름    | 위치 | 사유             |
        | 연결 폴더 "backend"  | "에셋"  | 끝   | parent_not_group |
        | 웹 링크 "API 명세"   | "에셋"  | 끝   | parent_not_group |
        | 없는 Node            | "에셋"  | 끝   | node_not_found   |
        | 최상위               | "  "    | 끝   | blank_name       |
        | 최상위               | "에셋"  | 3    | invalid_position |
        | 최상위               | "에셋"  | -1   | invalid_position |

  # ── 연결 파일·폴더 일괄 추가 ────────────────────────────

    Scenario: 여러 연결 대상을 한 작업으로 선택 순서대로 추가한다
      When 그룹 "개발" 아래에 다음 대상을 한 번에 추가한다
        | 표시 이름 | 대상 종류 | 경로              |
        | assets    | folder    | /design/assets    |
        | 회의록    | file      | /notes/meeting.md |
        | docs      | folder    | /docs             |
      Then 결과는 changed 하나다
      And "assets"는 UUID new-1, referenceID new-2, 정렬 순서 2, 기록 당시 경로 "/design/assets"인 연결 폴더다
      And "회의록"은 UUID new-3, referenceID new-4, 정렬 순서 3, 기록 당시 경로 "/notes/meeting.md"인 연결 파일이다
      And "docs"는 UUID new-5, referenceID new-6, 정렬 순서 4, 기록 당시 경로 "/docs"인 연결 폴더다

    Scenario: 일괄 추가 중 하나라도 유효하지 않으면 아무것도 추가하지 않는다
      When 그룹 "개발" 아래에 표시 이름 "assets"와 "   "인 두 대상을 한 번에 추가한다
      Then 결과는 rejected이고 사유는 blank_name이다

    Scenario: 일괄 추가 대상의 경로가 절대 경로가 아니면 아무것도 추가하지 않는다
      When 그룹 "개발" 아래에 경로 "/design/assets"와 "notes/meeting.md"인 두 대상을 한 번에 추가한다
      Then 결과는 rejected이고 사유는 invalid_path이다

    Scenario: 추가할 대상이 없으면 무변경이다
      When 그룹 "개발" 아래에 빈 대상 목록을 추가한다
      Then 결과는 unchanged이다

    Scenario: 기존 항목과 같은 이름·같은 경로의 대상도 별도 Node로 추가한다
      When 그룹 "개발" 아래에 표시 이름 "backend", 대상 종류 folder, 경로 "/dev/legacy-api"인 대상을 추가한다
      Then 결과는 changed이고 "개발" 아래에 "backend" Node가 서로 다른 UUID와 서로 다른 referenceID로 두 개 있다

  # ── 웹 링크 ─────────────────────────────────────────────

    Scenario: 웹 링크를 추가한다
      When 최상위에 이름 "디자인 시안", URL " https://figma.com/file/1 "인 웹 링크를 추가한다
      Then 결과는 changed이고 "디자인 시안"은 UUID new-1, URL "https://figma.com/file/1", 정렬 순서 2인 웹 링크다

    Scenario Outline: 웹 링크 URL을 바꾼다
      When "<대상>"의 URL을 <URL>로 바꾼다
      Then 결과는 <결과>이다

      Examples:
        | 대상     | URL                         | 결과                                         |
        | API 명세 | "https://example.com/v2"    | changed, UUID는 S와 같고 URL만 바뀐다        |
        | API 명세 | " https://example.com/api " | unchanged                                    |
        | API 명세 | "ftp://example.com"         | rejected, 사유 invalid_url                   |
        | API 명세 | ""                          | rejected, 사유 invalid_url                   |
        | backend  | "https://example.com"       | rejected, 사유 not_web_link                  |

  # ── 표시 이름 ───────────────────────────────────────────

    @A04
    Scenario: 표시 이름을 바꾸면 UUID와 배치·대상은 유지된다
      When "backend"의 표시 이름을 "api"로 바꾼다
      Then 결과는 changed이고 그 Node의 UUID, 부모, 정렬 순서, referenceID, 기록 당시 경로는 S와 같다
      And S의 그 Node 표시 이름은 여전히 "backend"이다

    @A04
    Scenario Outline: 같은 이름으로 확정하거나 빈 이름이면 기록할 변경이 없다
      When "backend"의 표시 이름을 <이름>으로 바꾼다
      Then 결과는 <결과>이다

      Examples:
        | 이름          | 결과                      |
        | "backend"     | unchanged                 |
        | "  backend "  | unchanged                 |
        | "   "         | rejected, 사유 blank_name |

  # ── 이동 ────────────────────────────────────────────────

    @A04
    Scenario: 다른 그룹으로 옮기면 양쪽 형제의 정렬 순서를 빈틈없이 다시 매긴다
      When "backend"를 최상위의 끝으로 옮긴다
      Then 결과는 changed이고 "backend"의 UUID와 대상은 S와 같다
      And "개발" 아래 정렬 순서는 "설계 메모" 0이다
      And 최상위 정렬 순서는 "개발" 0, "API 명세" 1, "backend" 2이다

    @A04
    Scenario: 그룹을 옮기면 자손은 그 그룹과 함께 옮겨진다
      Given S에 최상위 그룹 "보관"이 정렬 순서 2로 있다
      When 그룹 "개발"을 "보관" 아래 끝으로 옮긴다
      Then 결과는 changed이고 "개발"의 부모는 "보관"이다
      And "backend"와 "설계 메모"의 부모는 여전히 "개발"이고 정렬 순서도 그대로다

    @A04
    Scenario: 같은 부모의 같은 위치로 옮기면 무변경이다
      When "설계 메모"를 그룹 "개발" 아래 정렬 순서 1로 옮긴다
      Then 결과는 unchanged이다

    Scenario Outline: 이동을 거부하는 경우
      Given S에 그룹 "개발" 아래 그룹 "하위"가 정렬 순서 2로 있다
      When <대상>을 <목적지>로 옮긴다
      Then 결과는 rejected이고 사유는 <사유>이다

      Examples:
        | 대상              | 목적지                      | 사유             |
        | 그룹 "개발"       | 그룹 "개발" 아래            | cycle            |
        | 그룹 "개발"       | 그룹 "하위" 아래            | cycle            |
        | 연결 파일 "설계 메모" | 연결 폴더 "backend" 아래 | parent_not_group |
        | 없는 Node         | 최상위                      | node_not_found   |
        | "설계 메모"       | 최상위 정렬 순서 5          | invalid_position |

  # ── 형제 순서 ───────────────────────────────────────────

    @A04
    Scenario: 형제 안에서 순서를 바꾸면 사이의 형제만 밀린다
      When "설계 메모"를 그룹 "개발" 안에서 정렬 순서 0으로 옮긴다
      Then 결과는 changed이고 "개발" 아래 정렬 순서는 "설계 메모" 0, "backend" 1이다

    @A04
    Scenario Outline: 형제 순서 변경의 무변경과 거부
      When "설계 메모"를 그룹 "개발" 안에서 정렬 순서 <위치>로 옮긴다
      Then 결과는 <결과>이다

      Examples:
        | 위치 | 결과                            |
        | 1    | unchanged                       |
        | 2    | rejected, 사유 invalid_position |
        | -1   | rejected, 사유 invalid_position |

  # ── 제거 ────────────────────────────────────────────────

    Scenario: 그룹을 제거하면 자손도 함께 제거하고 남은 형제의 순서를 다시 매긴다
      When 그룹 "개발"을 제거한다
      Then 결과는 changed이고 "개발", "backend", "설계 메모"가 없다
      And 최상위 정렬 순서는 "API 명세" 0이다
      And S에는 "개발", "backend", "설계 메모"가 그대로 있다

    Scenario: 없는 Node는 제거할 수 없다
      When 없는 UUID의 Node를 제거한다
      Then 결과는 rejected이고 사유는 node_not_found이다

  # ── 연결 대상 교체 ──────────────────────────────────────

    @A03
    Scenario: 다른 대상으로 교체하면 새 referenceID를 만들고 이름·UUID·배치는 유지한다
      When "backend"의 대상을 identity가 different_target인 folder "/dev/new-api"로 교체한다
      Then 결과는 changed이고 "backend"의 referenceID는 new-1, 기록 당시 경로는 "/dev/new-api"이다
      And "backend"의 UUID, 표시 이름, 부모, 정렬 순서, 종류는 S와 같다
      And S의 "backend"는 여전히 referenceID ref-backend와 기록 당시 경로 "/dev/legacy-api"를 가진다

    @A03
    Scenario: 같은 실제 대상을 다시 고르면 무변경이다
      When "backend"의 대상을 identity가 same_target인 folder "/dev/legacy-api-moved"로 교체한다
      Then 결과는 unchanged이다

    @A03
    Scenario: 같은 대상인지 판정할 수 없으면 교체로 기록한다
      When "backend"의 대상을 identity가 undetermined인 folder "/dev/legacy-api"로 교체한다
      Then 결과는 changed이고 "backend"의 referenceID는 new-1이다

    Scenario Outline: 대상 교체를 거부하는 경우
      When <대상>의 대상을 identity가 different_target인 <대상 종류> "<경로>"로 교체한다
      Then 결과는 rejected이고 사유는 <사유>이다

      Examples:
        | 대상                  | 대상 종류 | 경로          | 사유                 |
        | 연결 폴더 "backend"   | file      | /dev/api.md   | target_kind_mismatch |
        | 연결 파일 "설계 메모" | folder    | /docs         | target_kind_mismatch |
        | 그룹 "개발"           | folder    | /dev          | not_linked_item      |
        | 웹 링크 "API 명세"    | file      | /api.md       | not_linked_item      |
        | 없는 Node             | folder    | /dev          | node_not_found       |
        | 연결 폴더 "backend"   | folder    | dev/relative  | invalid_path         |

  # ── 같은 대상 판정 (결정표 target_identity) ─────────────

  Rule: 같은 대상 판정은 파일 식별자와 볼륨 식별자를 함께 본다. 경로 문자열은 판정에 쓰지 않는다

    Scenario Outline: 식별자 비교로 같은 대상 여부를 판정한다
      Given 기존 대상과 새 대상의 file_identifier 비교는 <file_identifier>이고 volume_identifier 비교는 <volume_identifier>이다
      When 같은 대상인지 판정한다
      Then identity는 <identity>이다

      Examples:
        | file_identifier | volume_identifier | identity         |
        | same            | same              | same_target      |
        | same            | different         | different_target |
        | different       | same              | different_target |
        | different       | different         | different_target |
        | unavailable     | same              | undetermined     |
        | same            | unavailable       | undetermined     |
        | unavailable     | different         | undetermined     |
        | unavailable     | unavailable       | undetermined     |

    Scenario: 경로가 같아도 식별자가 다르면 다른 대상이다
      Given 기존 대상과 새 대상의 경로가 모두 "/dev/legacy-api"이다
      And file_identifier 비교는 different이고 volume_identifier 비교는 same이다
      When 같은 대상인지 판정한다
      Then identity는 different_target이다
