@task-W29
Feature: W29 Bishop 용도 아이콘
  Bishop(파일·폴더)마다 용도(문서·데이터·이미지·코드·참고·발표·할 일·디자인)를 골라 미트라에 용도 배지로 보인다. 용도는 구성의 일부다(0021).
  바꾸면 편집 연산 하나·revision 하나(원인 changePurpose, 화면 문구 "아이콘 변경")가 생기고, 같은 값이면 무변경이다(PRD §7).
  저장 키는 document, data, image, code, reference, presentation, todo, design이고 값이 없으면 배지 없음이다. 시각 규칙은 DESIGN.md 18장·0022를 따른다.
  Wing·웹 링크에는 용도가 없다. 보관된 Board에서는 바꿀 수 없다(0009).

  Background:
    Given Board "서비스 A"의 최상위에 Bishop 파일 "README.md", Bishop 폴더 "backend", 웹 링크 "API 명세", Wing "개발"이 있고 모두 용도가 없다

  # ── 편집 연산(Domain) ───────────────────────────────────

  @A04
  Scenario Outline: 용도를 바꾸면 그 값만 다른 새 구성이 된다
    When "README.md"의 용도를 <이전>에서 <이후>로 바꾸는 편집을 적용한다
    Then 결과는 changed이고 "README.md"의 용도만 <이후>이며 UUID·이름·부모·순서·연결 참조는 그대로다

    Examples:
      | 이전       | 이후          |
      | 없음       | document     |
      | document  | design       |
      | code      | 없음          |

  Scenario: 같은 용도로 바꾸면 무변경이다
    Given "README.md"의 용도가 todo다
    When "README.md"의 용도를 todo로 바꾸는 편집을 적용한다
    Then 결과는 unchanged다

  Scenario Outline: 용도를 바꿀 수 없는 편집은 거부한다
    When <대상>의 용도를 <값>으로 바꾸는 편집을 적용한다
    Then 결과는 <거부 사유>로 거부된다

    Examples:
      | 대상              | 값          | 거부 사유          |
      | Wing "개발"        | document   | not_linked_item   |
      | 웹 링크 "API 명세"  | reference  | not_linked_item   |
      | 없는 Node          | document   | node_not_found    |
      | Bishop "README.md" | music      | invalid_purpose   |

  Scenario: 폴더 Bishop도 용도를 가질 수 있다
    When "backend"의 용도를 code로 바꾸는 편집을 적용한다
    Then 결과는 changed이고 "backend"의 용도는 code다

  # ── 저장 형식 ───────────────────────────────────────────

  Scenario: 용도는 스냅샷에 저장되고 다시 읽어도 그대로다
    Given "README.md"의 용도가 document, "backend"의 용도가 code인 구성이다
    When 구성을 저장 형식으로 바꿨다가 다시 읽는다
    Then 두 용도와 나머지 값이 모두 같고 저장 형식 버전은 2다

  Scenario: 용도가 없던 버전 1 스냅샷은 용도 없음으로 읽는다
    Given 저장 형식 버전 1로 기록된 기존 revision이 있다
    When 그 revision의 구성을 읽는다
    Then 모든 Node의 용도는 없음이고 나머지 값은 기록 그대로다

  Scenario: 알 수 없는 용도 키도 값을 잃지 않는다
    Given 저장 형식 버전 2 스냅샷에 "README.md"의 용도 키가 "music"으로 기록돼 있다
    When 그 구성을 읽고 다른 Node의 이름만 바꿔 다시 저장한다
    Then "README.md"의 용도 키는 "music" 그대로 남고 화면에는 배지 없음으로 보인다

  Scenario Outline: Wing·웹 링크에 용도가 기록된 구성은 트리 검증을 통과하지 못한다
    Given <대상>에 용도 document가 기록된 구성이다
    When 트리 검증을 한다
    Then 형태 위반(purpose_not_allowed)으로 거부된다

    Examples:
      | 대상              |
      | Wing "개발"        |
      | 웹 링크 "API 명세"  |

  # ── 차이 비교(W16) ──────────────────────────────────────

  @A07
  Scenario: 용도만 바꾸면 비교 결과는 그 Node의 아이콘 변경 하나다
    Given 구성 B는 구성 A에서 "README.md"의 용도를 없음에서 document로 바꾼 것이다
    When A와 B를 비교한다
    Then 항목 변화는 "README.md" 하나이고 분류는 {아이콘 변경}이며 변경 전 용도는 없음, 변경 후 용도는 document다

  @A07
  Scenario: 이름과 용도를 함께 바꾸면 한 항목에 두 분류가 함께 담긴다
    Given 구성 B에서 "README.md"는 이름이 "읽어보기"이고 용도가 todo다
    When A와 B를 비교한다
    Then "README.md" 항목 하나에 분류 {이름 변경, 아이콘 변경}이 함께 있다

  # ── 화면 상태와 기록 ────────────────────────────────────

  @A04
  Scenario Outline: 고르는 곳에서 용도를 바꾸면 revision 하나가 남고 배지가 바뀐다
    Given 트리에서 Bishop 파일 "README.md"를 선택했다
    When <고르는 곳>에서 "<문구>"를 고른다
    Then 원인 changePurpose인 revision이 하나 늘고 "README.md"의 용도는 <키>다
    And 목록 행과 아이콘 타일은 미트라에 <키> 배지를 그리고, 접근성 라벨에 "<문구>"가 들어 있다

    Examples:
      | 고르는 곳                 | 문구 | 키        |
      | 인스펙터 "아이콘" 선택       | 문서 | document |
      | 오른쪽 클릭 "아이콘" 하위 메뉴 | 코드 | code     |

  Scenario: 기본을 고르면 배지가 없어지고 revision이 남는다
    Given "README.md"의 용도가 document이고 선택돼 있다
    When 인스펙터 "아이콘"에서 "기본"을 고른다
    Then 원인 changePurpose인 revision이 하나 늘고 "README.md"의 용도는 없음이며 배지가 없다

  Scenario: 지금 값과 같은 용도를 고르면 기록하지 않는다
    Given "README.md"의 용도가 document이고 선택돼 있다
    When 오른쪽 클릭 "아이콘" 하위 메뉴에서 체크된 "문서"를 다시 고른다
    Then revision 수는 그대로다

  Scenario: 용도 저장이 실패하면 안내하고 그대로 둔다
    Given "README.md"를 선택했고 다음 저장 직전에 실패하도록 설정되어 있다
    When 인스펙터 "아이콘"에서 "이미지"를 고른다
    Then 저장하지 못했다는 안내가 보이고 "README.md"의 용도와 revision 수는 그대로다

  Scenario Outline: 용도를 고를 수 없는 경우 고르는 곳이 꺼져 있다
    Given <상태>
    Then 인스펙터 "아이콘" 선택과 오른쪽 클릭 "아이콘" 하위 메뉴는 꺼져 있거나 보이지 않는다

    Examples:
      | 상태                                  |
      | Board "서비스 A"가 보관돼 있고 "README.md"를 선택했다 |
      | Wing "개발"을 선택했다                    |
      | 웹 링크 "API 명세"를 선택했다              |
      | 아무것도 선택하지 않았다                    |

  Scenario: 고르는 곳은 지금 값에 체크 표시를 한다
    Given "README.md"의 용도가 reference이고 선택돼 있다
    Then 인스펙터 "아이콘" 선택과 오른쪽 클릭 "아이콘" 하위 메뉴에서 "참고"에 체크 표시가 있다

  # ── 기호와 종류 문구 ────────────────────────────────────

  Scenario Outline: 기호는 설정과 용도에 따라 정해진다
    Given 설정의 "Bishop 아이콘"이 <설정>이고 <항목>의 용도가 <용도>다
    Then <항목>의 기호는 <기호>다

    Examples:
      | 설정          | 항목               | 용도       | 기호                                |
      | 기호(기본)     | Bishop 파일 "README.md" | 없음      | Bishop 심볼                        |
      | 기호(기본)     | Bishop 파일 "README.md" | document | Bishop 심볼 + document 배지           |
      | 기호(기본)     | Bishop 폴더 "backend"   | 없음      | Bishop 폴더 심볼                    |
      | 기호(기본)     | Bishop 폴더 "backend"   | code     | Bishop 심볼 + code 배지(폴더 배지를 대신) |
      | 파일 종류 아이콘 | Bishop 파일 "README.md" | document | 파일 종류 아이콘 + Bishop 배지(용도 배지 없음) |

  Scenario Outline: 종류 문구는 파일과 폴더 Bishop을 구분한다
    Then <항목>의 종류 문구는 "<문구>"다

    Examples:
      | 항목               | 문구          |
      | Bishop 파일 "README.md" | Bishop       |
      | Bishop 폴더 "backend"   | Bishop · 폴더 |

  Scenario: 파일 종류 아이콘 설정에서도 용도는 인스펙터와 접근성 라벨에 보인다
    Given 설정의 "Bishop 아이콘"이 "파일 종류 아이콘"이고 "README.md"의 용도가 document다
    Then 인스펙터의 "아이콘" 값은 "문서"이고 "README.md"의 접근성 라벨에 "문서"가 들어 있다

  Scenario: 문구가 String Catalog에 있다
    Then String Catalog에 "아이콘", "기본", "문서", "데이터", "이미지", "코드", "참고", "발표", "할 일", "디자인", "아이콘 변경", "Bishop · 폴더" 문구가 있다
