@task-W09
Feature: W09 연결 대상 변경
  Bishop의 표시 이름·UUID·부모·순서는 그대로 두고 실제 대상만 다른 파일·폴더로 바꾼다.
  흐름은 대상 고르기 → 확인(기존 경로와 새 경로) → 확정이다. 확인과 확정 모두 W03 결정표 target_identity로 같은 대상인지 판정한다(0004).
  기존 대상의 식별자는 기존 참조의 북마크를 해석한 위치에서 구하고, 해석하지 못하면 식별자를 얻을 수 없는 것으로 본다(판정 불가).
  확정은 새 참조 레코드(최초 경로 = 새 경로)와 대상 교체 revision 하나를 한 저장 단위로 커밋한다(W05). 이전 참조 레코드와 과거 revision은 바뀌지 않는다.
  서비스 시나리오는 임시 디렉토리의 실제 파일과 실제 저장소를 쓴다.

  Background:
    Given Board "서비스 A"의 그룹 "개발" 안에 정렬 순서 0으로 "/targets/legacy-api" 폴더를 연결한 Bishop "backend"가 있다

  # ── 서비스 ──────────────────────────────────────────────

  @A03
  Scenario: 다른 폴더로 교체하면 이름·UUID·배치는 유지하고 새 참조를 쓴다
    Given 임시 디렉토리에 폴더 "new-api"가 있다
    When "backend"의 대상으로 "new-api"를 골라 확인한 뒤 확정한다
    Then 확인 정보는 기존 경로 "/targets/legacy-api", 새 경로 "new-api"의 경로, 판정 different_target이다
    And 결과는 committed이고 원인 replaceTarget인 revision이 하나 늘어난다
    And "backend"의 UUID·표시 이름·부모·정렬 순서는 그대로이고 referenceID는 새 값이며 기록 당시 경로는 "new-api"의 경로다
    And 새 참조 레코드는 최초 경로가 "new-api"의 경로이고 해석하면 "new-api"를 가리킨다

  @A03
  Scenario: 교체 전 revision은 기존 대상을 그대로 가진다
    Given "backend"를 폴더 "new-api"로 교체했다
    When 교체 직전 revision의 구성을 읽는다
    Then 그 구성의 "backend"는 기존 referenceID와 기록 당시 경로 "/targets/legacy-api"를 가진다
    And 기존 참조 레코드는 지워지지 않고 해석하면 여전히 "legacy-api"를 가리킨다

  @A03
  Scenario: 같은 대상을 다시 고르면 같은 대상이라고 알리고 아무것도 기록하지 않는다
    When "backend"의 대상으로 "legacy-api"를 다시 골라 확인한다
    Then 확인 정보의 판정은 same_target이다
    When 그래도 확정한다
    Then 결과는 unchanged이고 revision 수와 참조 레코드 수는 그대로다

  @A03
  Scenario: 같은 볼륨 안에서 이름을 바꾼 기존 대상을 고르면 같은 대상이다
    Given "legacy-api" 폴더 이름을 "legacy-api-renamed"로 바꿨다
    When "backend"의 대상으로 "legacy-api-renamed"를 골라 확인한다
    Then 확인 정보의 판정은 same_target이다

  @A03
  Scenario: 기존 대상을 찾을 수 없으면 판정 불가로 알리고, 확정하면 교체로 기록한다
    Given "legacy-api" 폴더가 지워졌다
    And 임시 디렉토리에 폴더 "new-api"가 있다
    When "backend"의 대상으로 "new-api"를 골라 확인한다
    Then 확인 정보의 판정은 undetermined이고 확정하면 교체로 기록된다는 안내 표시가 있다
    When 확정한다
    Then 결과는 committed이고 "backend"는 새 referenceID를 가진다

  Scenario Outline: 교체할 수 없는 요청은 아무것도 기록하지 않는다
    Given <조건>
    When <요청>
    Then 결과는 <사유>이고 revision 수와 참조 레코드 수는 그대로다

    Examples:
      | 조건                                   | 요청                                             | 사유                              |
      | 임시 디렉토리에 파일 "api.md"가 있다      | "backend"의 대상으로 파일 "api.md"를 고른다         | 종류가 달라 거부(target_kind_mismatch) |
      | 그룹 "개발"이 있다                       | 그룹 "개발"의 대상 변경을 요청한다                   | 연결 항목이 아니어서 거부(not_linked_item) |
      | 고른 폴더 "new-api"가 확인 뒤 지워진다     | 확인한 교체를 확정한다                              | 새 대상에 연결할 수 없어 거부            |
      | Board "서비스 A"가 확인 뒤 보관된다        | 확인한 교체를 확정한다                              | 보관된 Board라 거부(archived)          |
      | "backend"가 확인 뒤 제거된다              | 확인한 교체를 확정한다                              | 항목이 없어 거부(node_not_found)        |

  Scenario: 확정할 때 같은 대상인지 다시 판정한다
    Given 폴더 "new-api"를 골라 확인했고 확인 정보의 판정은 different_target이다
    And 확정하기 전에 "backend"의 기존 대상 "legacy-api"가 지워진다
    When 확정한다
    Then 결과는 committed이고 커밋된 교체는 확정 시점의 판정(undetermined)으로 기록된다

  Scenario: 저장이 실패하면 교체가 남지 않는다
    Given 임시 디렉토리에 폴더 "new-api"가 있고 다음 저장 직전에 실패하도록 설정되어 있다
    When "backend"를 "new-api"로 교체한다
    Then 저장 실패 오류가 나고 "backend"의 referenceID·기록 당시 경로와 참조 레코드 수는 그대로다

  Scenario: 교체는 기존 대상과 새 대상 파일을 바꾸지 않는다
    Given "legacy-api"와 "new-api"의 목록·수정 시각·권한을 기억한다
    When "backend"를 "new-api"로 교체한다
    Then 두 폴더의 목록·수정 시각·권한은 처음과 같다

  # ── 화면 ────────────────────────────────────────────────

  Scenario Outline: 연결 대상 변경은 선택한 Bishop의 종류에 맞는 대상만 고르게 한다
    Given 트리에서 <Bishop>을 선택했다
    When "연결 대상 변경"을 실행한다
    Then 선택 창은 <고를 수 있는 것>만 하나 고를 수 있다

    Examples:
      | Bishop                 | 고를 수 있는 것 |
      | Bishop 폴더 "backend"   | 폴더          |
      | Bishop 파일 "설계 메모" | 파일          |

  Scenario: 대상을 고르면 기존·새 경로를 보여 주는 확인 창을 띄우고, 확정해야 바뀐다
    Given 트리에서 Bishop "backend"를 선택했다
    When "연결 대상 변경"에서 폴더 "new-api"를 고른다
    Then 확인 창에 기존 경로 "/targets/legacy-api"와 새 경로가 보이고 아직 revision은 늘지 않는다
    When "변경"을 고른다
    Then 확인 창이 닫히고 트리와 상세 영역의 "backend" 대상이 새 경로로 바뀐다

  Scenario Outline: 확인 창은 판정에 따라 안내와 확정 동작을 다르게 보여 준다
    Given 트리에서 Bishop "backend"를 선택했다
    When "연결 대상 변경"에서 <고른 대상>을 고른다
    Then 확인 창은 <안내>

    Examples:
      | 고른 대상                          | 안내                                                   |
      | 다른 폴더 "new-api"                | 기존·새 경로와 "변경" 동작을 보여 준다                    |
      | 같은 폴더 "legacy-api"             | 이미 연결된 대상이라고 알리고 "변경" 없이 "닫기"만 보여 준다 |
      | 기존 대상이 지워진 상태의 "new-api" | 같은 대상인지 확인할 수 없어 교체로 기록된다고 알리고 "변경"을 보여 준다 |

  Scenario Outline: 고르기를 취소하거나 확인 창을 닫으면 아무것도 기록하지 않는다
    Given 트리에서 Bishop "backend"를 선택했다
    When <동작>
    Then revision 수는 그대로이고 "backend"의 대상은 그대로다

    Examples:
      | 동작                                         |
      | "연결 대상 변경"의 선택 창을 취소한다           |
      | 폴더 "new-api"를 고른 뒤 확인 창에서 "취소"를 고른다 |

  Scenario Outline: Bishop이 아니거나 보관된 Board면 연결 대상 변경을 시작하지 않는다
    Given <상태>
    When "연결 대상 변경"을 실행한다
    Then 선택 창을 열지 않는다<추가>

    Examples:
      | 상태                                 | 추가                                         |
      | 트리에서 그룹 "개발"을 선택했다         |                                              |
      | 트리에서 아무 항목도 선택하지 않았다     |                                              |
      | 보관된 Board의 Bishop을 선택했다        | 그리고 보관된 Board는 바꿀 수 없다는 안내를 보여 준다 |

  Scenario: 새 대상에 연결할 수 없거나 저장에 실패하면 안내하고 대상은 그대로다
    Given 트리에서 Bishop "backend"를 선택했고 폴더 "new-api"를 고른 뒤 확인 창이 보인다
    And "new-api"가 지워졌다
    When "변경"을 고른다
    Then 연결하지 못했다는 안내가 보이고 "backend"의 대상은 그대로다

  Scenario: 연결 대상 변경 명령이 메뉴와 상세 영역에 있다
    When 앱 메뉴와 Bishop을 선택한 상세 영역을 확인한다
    Then 파일 메뉴에 "연결 대상 변경…"(⇧⌘R)이 있고 상세 영역에 "연결 대상 변경" 버튼이 있다
    And String Catalog에 "연결 대상 변경" 문구가 있다
