@task-W05
Feature: W05 구성 변경 커밋 서비스와 Board 만들기
  구성 변경 서비스는 확정된 사용자 작업 하나를 받아 현재 구성(현재 revision의 스냅샷, 0007)에 W03 편집 연산을 적용하고,
  changed 결과만 새 revision 추가와 현재 revision 이동을 한 저장 단위로 커밋한다.
  서비스의 결과는 committed(새 revision 목록 정보와 새 현재 구성), unchanged, rejected(사유) 중 하나이며,
  committed는 저장이 실제로 성공한 뒤에만 돌려준다. 저장 실패는 결과가 아니라 오류다.
  연결 파일·폴더 추가와 대상 교체는 대상마다 북마크 바이트를 함께 받는다. 커밋이 새로 쓰는 referenceID마다 ResourceReference 레코드
  (최초 경로 = 기록 당시 경로, 종류, 북마크 바이트)를 같은 저장 단위로 저장한다. 그래서 커밋 단위는 새 revision, 현재 revision 이동,
  새 참조 레코드다(불변식 5).
  시각과 UUID는 주입된 시계와 생성기가 내준다. 시계는 요청마다 한 번 읽는다. 실패 지점은 모든 변경을 저장 단위에 올린 뒤, 저장 직전에 있다.
  거부 사유는 project_not_found → archived → W03 편집 결과 순서로 판정한다.
  화면 용어 Board는 데이터 모델의 Project다(0006). 아래 단계는 저장 결과를 Project로 적는다.
  모든 시나리오는 테스트마다 임시 디렉토리의 실제 SwiftData 저장소를 쓴다.

  Background:
    Given 임시 디렉토리의 저장소로 구성 변경 서비스를 연다
    And 시계는 T0부터 요청마다 1초씩 증가한 시각을 내준다

  # ── Board 만들기 ────────────────────────────────────────

  @A01
  Scenario: Board를 만들면 빈 초기 구성의 첫 revision이 기록된다
    When 이름 "  서비스 A "로 Board를 만든다
    Then 결과는 committed이고 새 Project가 하나 저장된다
    And 그 Project의 revision은 하나이며 순번 1, 원인 created, 기록 시각 T0, 프로젝트 이름 "서비스 A"이다
    And Project의 생성 시각은 첫 revision의 기록 시각 T0와 같다
    And 현재 revision은 그 revision이고 현재 구성은 Node가 없는 "서비스 A" 구성이다
    And Project의 보관 시각과 출처는 없다

  @A01
  Scenario: Board를 만들고 그룹을 추가해도 파일 시스템에 디렉토리나 파일이 생기지 않는다
    Given 임시 디렉토리 안의 파일 목록을 기억한다
    When 이름 "서비스 A"로 Board를 만들고 최상위에 그룹 "개발"과 그 안에 그룹 "하위"를 추가한다
    Then 임시 디렉토리에서 바뀌거나 생긴 파일은 저장소 파일 묶음뿐이다
    And 새 디렉토리는 생기지 않는다

  Scenario: 빈 이름으로는 Board를 만들 수 없다
    When 이름 "   "로 Board를 만든다
    Then 결과는 rejected이고 사유는 blank_name이다
    And Project와 revision은 저장되지 않는다

  Scenario: 같은 이름의 Board를 여러 개 만들 수 있다
    When 이름 "서비스 A"로 Board를 두 번 만든다
    Then 서로 다른 UUID의 Project 두 개가 있고 각각 순번 1 revision을 가진다

  # ── 구성 변경 커밋 ──────────────────────────────────────

  @A01
  Scenario: 변경을 확정하면 새 revision과 현재 구성이 함께 저장된다
    Given Board "서비스 A"가 있다
    When 최상위에 그룹 "개발"을 추가한다
    Then 결과는 committed이고 새 revision은 순번 2, 원인 addGroup, 다음 시각의 기록이다
    And 현재 revision은 순번 2 revision이고 현재 구성에 그룹 "개발"이 있다
    And 저장소를 닫고 다시 열어도 현재 revision과 revision 목록이 같다
    And 순번 1 revision의 구성에는 그룹 "개발"이 없다

  Scenario Outline: 편집 종류는 revision 원인으로 기록된다
    Given 그룹 "개발"과 연결 폴더 "backend", 웹 링크 "API 명세"가 있는 Board가 있다
    When <편집>을 확정한다
    Then 새 revision의 원인은 <원인>이다

    Examples:
      | 편집                                           | 원인           |
      | 프로젝트 이름을 "서비스 B"로 바꾸기            | renameProject  |
      | 최상위에 그룹 "문서" 추가                      | addGroup       |
      | 그룹 "개발"에 연결 파일 하나 추가              | addLinkedItems |
      | 최상위에 웹 링크 추가                          | addWebLink     |
      | "backend" 표시 이름을 "api"로 바꾸기           | renameNode     |
      | "API 명세" URL 바꾸기                          | changeURL      |
      | "backend"를 최상위로 옮기기                    | move           |
      | "API 명세" 제거                                | remove         |
      | "backend"를 다른 대상으로 교체                 | replaceTarget  |

  Scenario: 연결 대상 추가는 새 참조 레코드를 revision과 함께 저장한다
    Given Board "서비스 A"에 그룹 "개발"이 있다
    When 그룹 "개발"에 북마크 바이트 B1의 folder "/design/assets"와 B2의 file "/notes/meeting.md"를 한 번에 추가한다
    Then 결과는 committed이고 새 Node 두 개의 referenceID마다 참조 레코드가 하나씩 저장된다
    And "assets"의 참조 레코드는 최초 경로 "/design/assets", 종류 folder, 북마크 바이트 B1이다
    And "meeting.md"의 참조 레코드는 최초 경로 "/notes/meeting.md", 종류 file, 북마크 바이트 B2이다
    And 현재 구성의 어떤 referenceID도 참조 레코드 없이 남지 않는다

  @A13
  Scenario: 대상 교체는 새 참조 레코드를 저장하고 이전 참조 레코드는 그대로 둔다
    Given Board "서비스 A"에 참조 레코드 ref-backend를 가진 연결 폴더 "backend"가 있다
    When "backend"를 북마크 바이트 B3의 folder "/dev/new-api"로 교체한다(identity different_target)
    Then 새 referenceID의 참조 레코드가 최초 경로 "/dev/new-api", 북마크 바이트 B3으로 저장된다
    And ref-backend 참조 레코드는 그대로 남는다

  Scenario: 같은 대상을 다시 고른 교체는 참조 레코드도 만들지 않는다
    Given Board "서비스 A"에 연결 폴더 "backend"가 있다
    When "backend"를 identity same_target인 folder로 교체한다
    Then 결과는 unchanged이고 참조 레코드 수는 그대로다

  @A13
  Scenario: 연결 대상 추가의 저장이 실패하면 Node·revision·참조 레코드가 모두 남지 않는다
    Given Board "서비스 A"에 그룹 "개발"이 있다
    And 다음 저장 직전에 실패하도록 실패 지점을 설정한다
    When 그룹 "개발"에 북마크 바이트 B1의 folder "/design/assets"를 추가한다
    Then 저장 실패 오류가 난다
    And 같은 서비스와 다시 연 저장소 모두에서 revision 수, 현재 revision, 참조 레코드 수가 실패 전과 같다

  Scenario Outline: 북마크 바이트 수가 대상 수와 맞지 않는 요청은 거부한다
    Given Board "서비스 A"에 그룹 "개발"과 연결 폴더 "backend"가 있다
    When <요청>을 보낸다
    Then 결과는 rejected이고 사유는 access_mismatch이다
    And revision 수와 참조 레코드 수는 그대로다

    Examples:
      | 요청                                                    |
      | 대상 두 개를 추가하면서 북마크 바이트를 하나만 준 요청   |
      | "backend" 대상 교체에 북마크 바이트를 주지 않은 요청     |
      | 그룹 추가에 북마크 바이트를 준 요청                      |

  Scenario: 무변경 결과는 저장하지 않는다
    Given Board "서비스 A"에 revision 2개가 있다
    When 프로젝트 이름을 " 서비스 A "로 바꾼다
    Then 결과는 unchanged이다
    And revision 수와 현재 revision은 그대로다

  Scenario: 거부된 편집은 저장하지 않는다
    Given Board "서비스 A"가 있다
    When 없는 Node의 표시 이름을 바꾼다
    Then 결과는 rejected이고 사유는 node_not_found이다
    And revision 수와 현재 revision은 그대로다

  Scenario: 보관된 Board의 구성은 바꿀 수 없다
    Given Board "서비스 A"가 보관되어 있다
    When 최상위에 그룹 "개발"을 추가한다
    Then 결과는 rejected이고 사유는 archived이다
    And revision 수와 현재 revision은 그대로다

  Scenario: 없는 Board는 바꿀 수 없다
    Given Board "서비스 A"가 있다
    When 없는 Project UUID에 그룹을 추가한다
    Then 결과는 rejected이고 사유는 project_not_found이다
    And 저장소의 Project 수와 revision 수는 그대로다

  Scenario: 보관된 Board의 거부 사유는 편집 자체의 사유보다 먼저다
    Given Board "서비스 A"가 보관되어 있다
    When 없는 Node의 표시 이름을 바꾼다
    Then 결과는 rejected이고 사유는 archived이다

  Scenario: 현재 구성을 읽을 수 없으면 오류를 내고 빈 구성으로 대신하지 않는다
    Given Board "서비스 A"의 현재 revision 스냅샷 바이트가 손상되어 있다
    When 최상위에 그룹 "개발"을 추가한다
    Then "현재 구성을 읽을 수 없음" 오류가 난다
    And revision 수와 현재 revision은 그대로이고 빈 구성으로 새 revision을 만들지 않는다

  # ── 저장 실패 (A13) ─────────────────────────────────────

  @A13
  Scenario: 저장이 실패하면 오류를 돌려주고 새 revision과 현재 구성 변경이 모두 남지 않는다
    Given Board "서비스 A"에 revision 1개가 있다
    And 다음 저장 직전에 실패하도록 실패 지점을 설정한다
    When 최상위에 그룹 "개발"을 추가한다
    Then 저장 실패 오류가 나고 committed 결과는 돌아오지 않는다
    And 같은 서비스에서 읽은 현재 revision과 revision 목록은 실패 전과 같다
    And 저장소를 닫고 다시 열어도 현재 revision과 revision 목록은 실패 전과 같다

  @A13
  Scenario: 저장 실패 뒤 같은 편집을 다시 보내면 한 번만 기록된다
    Given Board "서비스 A"에 revision 1개가 있다
    And 다음 저장 직전에 한 번만 실패하도록 실패 지점을 설정한다
    When 최상위에 그룹 "개발"을 추가하다 실패하고, 같은 편집을 다시 보낸다
    Then 두 번째 결과는 committed이고 새 revision의 순번은 2이다
    And 현재 구성에 그룹 "개발"은 하나뿐이다

  @A13
  Scenario: 저장 실패 뒤의 다음 변경은 순번을 건너뛰지 않는다
    Given Board "서비스 A"에 revision 1개가 있다
    And 다음 저장 직전에 한 번만 실패하도록 실패 지점을 설정한다
    When 최상위에 그룹 "개발"을 추가하다 실패하고, 다시 최상위에 그룹 "문서"를 추가한다
    Then 두 번째 결과는 committed이고 새 revision의 순번은 2이다
    And 현재 구성에는 "문서"만 있고 "개발"은 없다

  @A13
  Scenario: Board 만들기 중 저장이 실패하면 Project와 revision이 모두 남지 않는다
    Given 다음 저장 직전에 한 번만 실패하도록 실패 지점을 설정한다
    When 이름 "서비스 A"로 Board를 만든다
    Then 저장 실패 오류가 난다
    And 같은 서비스에서 읽은 Project 목록은 비어 있다
    When 이어서 이름 "서비스 B"로 Board를 만든다
    Then 결과는 committed이다
    And 저장소를 다시 열면 Project는 "서비스 B" 하나이고 revision도 그 Project의 순번 1 하나뿐이다

  # ── 순서와 직렬화 ───────────────────────────────────────

  Scenario: 같은 Board에 동시에 들어온 변경은 하나씩 커밋되어 순번이 연속된다
    Given Board "서비스 A"에 revision 1개가 있다
    When 서로 다른 그룹 20개를 추가하는 요청을 동시에 보낸다
    Then 20개 결과가 모두 committed이다
    And revision 순번은 1부터 21까지 빠짐도 중복도 없다
    And 현재 구성에는 그룹 20개가 모두 있다

  Scenario: 시계가 뒤로 가도 순번은 계속 증가한다
    Given Board "서비스 A"가 시각 T10에 만들어졌다
    And 시계가 다음에 T5를 내준다
    When 최상위에 그룹 "개발"을 추가한다
    Then 새 revision의 순번은 2이고 기록 시각은 T5이다
    And revision 목록은 순번 1, 2 순서다

  Scenario: Board마다 순번을 따로 센다
    Given Board "서비스 A"와 Board "서비스 B"가 있다
    When "서비스 A"에 그룹을 두 번, "서비스 B"에 그룹을 한 번 추가한다
    Then "서비스 A"의 마지막 순번은 3이고 "서비스 B"의 마지막 순번은 2이다
