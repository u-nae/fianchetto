@task-W04
Feature: W04 SwiftData 스키마 V1과 저장소 열기
  영구 저장소는 Project, Revision, ResourceReference, Checkpoint(첨부 참조 포함)를 저장한다.
  현재 구성은 Project의 현재 revision이 가리키는 스냅샷이며 Node 레코드는 없다(0007).
  저장소 모델은 Persistence 밖으로 나가지 않고, 경계에서 Domain 레코드 값으로 바뀐다.
  모든 시나리오는 테스트마다 새로 만든 임시 디렉토리의 저장소 파일을 쓰고, 끝나면 지운다.

  # ── 저장과 재오픈 ───────────────────────────────────────

  Scenario: 저장한 레코드는 저장소를 닫았다 다시 열어도 같은 값으로 읽힌다
    Given 임시 디렉토리에 새 저장소를 연다
    And 다음 레코드를 저장한다
      | 레코드            | 내용                                                                                  |
      | Project           | UUID P, 생성 시각 T0, 현재 revision R2, 보관 시각 없음, 출처 없음                     |
      | Revision R1       | Project P, 순번 1, 기록 시각 T0, 원인 created, 프로젝트 이름 "서비스 A", 스냅샷 S1    |
      | Revision R2       | Project P, 순번 2, 기록 시각 T1, 원인 renameNode, 프로젝트 이름 "서비스 A", 스냅샷 S2 |
      | ResourceReference | UUID ref-backend, 최초 경로 "/dev/legacy-api", 종류 folder, 북마크 바이트 B1, 마지막 해석 경로 "/dev/legacy-api" |
      | Checkpoint        | UUID C1, revision R2, 제목 "인증 리팩토링 1차 완료", 진행 메모 M, 다음 할 일 N, 작성 시각 T1, 첨부 없음 |
    When 저장소를 닫고 같은 파일로 다시 연다
    Then 읽은 Domain 레코드는 저장한 값과 모두 같다
    And R2의 스냅샷을 디코딩하면 S2와 같은 구성 스냅샷이다

  Scenario: revision 목록 정보는 스냅샷을 디코딩하지 않고 읽는다
    Given 저장소에 순번 1의 정상 revision과 스냅샷 바이트가 손상된 순번 2의 revision이 있다
    When Project P의 revision 목록 정보를 읽는다
    Then 두 revision의 순번, 기록 시각, 원인, 프로젝트 이름이 순번 순서로 읽힌다
    And 순번 2의 스냅샷을 디코딩할 때만 손상 오류가 난다

  Scenario Outline: revision 원인과 복원 출처를 그대로 보존한다
    Given 원인이 <원인>이고 복원 출처 revision이 <복원 출처>인 revision을 저장한다
    When 저장소를 닫고 다시 열어 그 revision을 읽는다
    Then 원인은 <원인>이고 복원 출처 revision은 <복원 출처>이다

    Examples:
      | 원인            | 복원 출처 |
      | created         | 없음      |
      | renameProject   | 없음      |
      | addGroup        | 없음      |
      | addLinkedItems  | 없음      |
      | addWebLink      | 없음      |
      | renameNode      | 없음      |
      | changeURL       | 없음      |
      | move            | 없음      |
      | remove          | 없음      |
      | replaceTarget   | 없음      |
      | restored        | R1        |
      | duplicated      | 없음      |
      | imported        | 없음      |

  Scenario Outline: 프로젝트의 보관 시각과 출처를 그대로 보존한다
    Given 보관 시각이 <보관 시각>이고 출처가 <출처>인 Project를 저장한다
    When 저장소를 닫고 다시 열어 그 Project를 읽는다
    Then 보관 시각은 <보관 시각>이고 출처는 <출처>이다

    Examples:
      | 보관 시각 | 출처                                          |
      | 없음      | 없음                                          |
      | T5        | 없음                                          |
      | 없음      | 복제, 원본 Project P0, 원본 revision R9       |
      | T5        | 가져오기, 원본 Project P0, 원본 revision R9   |

  Scenario: 한 revision에 체크포인트 여러 개와 첨부 참조를 저장한다
    Given revision R2에 체크포인트 C1과 C2를 저장한다
    And C2에는 첨부 참조 두 개가 있다
      | UUID | 앱 내부 상대 경로        | 형식       | 바이트 수 | 순서 |
      | A1   | attachments/A1.png       | image/png  | 1024      | 0    |
      | A2   | attachments/A2.jpg       | image/jpeg | 2048      | 1    |
    When 저장소를 닫고 다시 열어 R2의 체크포인트를 읽는다
    Then C1과 C2가 모두 R2에 연결되어 있다
    And C2의 첨부 참조는 A1, A2 순서로 같은 값이다
    And C1의 진행 메모와 다음 할 일이 비어 있으면 빈 값 그대로 읽힌다

  Scenario: 연결 참조의 북마크와 해석 경로를 갱신해도 revision 스냅샷은 바뀌지 않는다
    Given revision R2의 스냅샷이 ref-backend를 기록 당시 경로 "/dev/legacy-api"로 가진다
    When ref-backend의 북마크 바이트를 B2로, 마지막 해석 경로를 "/Volumes/ext/legacy-api"로 바꿔 저장한다
    And 저장소를 닫고 다시 연다
    Then ref-backend는 북마크 바이트 B2와 마지막 해석 경로 "/Volumes/ext/legacy-api"를 가진다
    And ref-backend의 최초 경로는 "/dev/legacy-api" 그대로다
    And R2의 스냅샷 바이트는 갱신 전과 같다

  Scenario: 저장된 revision 스냅샷 바이트는 읽고 다시 저장해도 바뀌지 않는다
    Given revision R1을 저장하고 스냅샷 바이트를 기억한다
    When 저장소를 다시 열어 R1을 Domain 레코드로 읽고, 같은 저장소에 다른 revision을 추가해 저장한다
    Then R1의 스냅샷 바이트는 처음과 같다

  # ── 저장소 열기 ─────────────────────────────────────────

  Scenario: 저장소 파일이 없으면 새 저장소를 만든다
    Given 임시 디렉토리에 저장소 파일이 없다
    When 그 위치로 저장소를 연다
    Then 저장소가 열리고 Project가 하나도 없다

  Scenario: 저장소 디렉토리가 없으면 만들고 연다
    Given 임시 디렉토리 아래 "Fianchetto" 하위 디렉토리가 없다
    When 그 하위 디렉토리 안의 저장소 파일 위치로 저장소를 연다
    Then 하위 디렉토리가 만들어지고 저장소가 열린다

  Scenario Outline: 기존 저장소를 열 수 없으면 오류를 돌려주고 파일을 바꾸지 않는다
    Given 임시 디렉토리에 <상태>인 저장소 파일이 있다
    When 그 위치로 저장소를 연다
    Then 저장소 열기는 "저장소를 열 수 없음" 오류로 실패하고 오류에 저장소 위치가 담긴다
    And 기존 저장소 파일의 바이트는 열기 전과 같다
    And 기존 파일이 지워지거나 빈 저장소로 바뀌지 않는다

    Examples:
      | 상태                                         |
      | 저장소가 아닌 임의 바이트로 채워진 손상 상태  |
      | 앱이 모르는 스키마 버전으로 만든 상태         |
      | 읽기 권한이 없는 상태                         |

  Scenario: 기본 저장소 위치는 앱의 Application Support 아래다
    When 기본 저장소 위치를 구한다
    Then 위치는 앱 컨테이너의 Application Support 디렉토리 아래 앱 전용 하위 디렉토리에 있다

  # ── 스키마 이전 ─────────────────────────────────────────

  @A18
  Scenario: 스키마 V1에서 만든 데이터는 다음 스키마 버전으로 이전한 뒤에도 유지된다
    Given 스키마 V1으로 연 저장소에 Project P, revision R1·R2, ref-backend, 체크포인트 C1을 저장하고 닫는다
    When 같은 파일을 V1 → V2 이전 계획으로 연다
    Then Project P, revision R1·R2, ref-backend, 체크포인트 C1이 모두 같은 값으로 읽힌다
    And R2의 스냅샷을 디코딩하면 저장 전과 같은 구성 스냅샷이다

  @A18
  Scenario: 앱의 스키마 버전 목록은 V1에서 시작하고 이전 계획이 그 목록을 따른다
    When 앱의 스키마 이전 계획을 확인한다
    Then 첫 스키마는 버전 1.0.0이고 Project, Revision, ResourceReference, Checkpoint, 첨부 참조 모델을 포함한다
    And 이전 계획의 스키마 목록은 V1 하나이며 이전 단계는 없다

  # ── 경계 ────────────────────────────────────────────────

  Scenario: 저장소 모델 프레임워크는 Persistence와 앱 조립 계층에서만 쓴다
    When 소스 구조를 검사한다
    Then SwiftData를 import하는 소스는 Persistence와 App 폴더에만 있다
    And Domain·Services·Features·Platform 폴더의 소스는 SwiftData를 import하지 않는다
