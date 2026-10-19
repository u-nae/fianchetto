# 명세 브리프 — W22 체크포인트 저장과 재개

## 1. 작업 항목

| task_id | title | route | acceptance_refs |
| --- | --- | --- | --- |
| W22 | 체크포인트 저장과 재개 | BOTH | A10 |

기준 문서:
- docs/PRD.md (9194c2af1e20)
- docs/TECH_STACK.md (3b623d55c2cc)

run_id: t-w22-72ee8b76

## 2. 승인된 명세

### .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature

```gherkin
@task-W22
Feature: W22 체크포인트 저장과 재개
  현재 구성에서 파일 메뉴 '체크포인트 저장…' 또는 툴바 깃발 버튼으로 시트를 열면, 여는 순간의 현재 revision을 고정하고 제목(필수)·진행 메모·다음 할 일(선택)을
  받아 그 revision에 불변 체크포인트를 붙인다(PRD §6-G, A10). 입력 중에는 revision을 만들지 않고, 시트가 열린 동안 구성 편집을 막는다.
  같은 revision에 여러 체크포인트를 붙일 수 있고, 저장한 체크포인트는 고치지 않는다(고치려면 새로 저장한다). 보관된 Board에서는 저장을 거부한다(0009).
  이력 탭에는 체크포인트마다 행 하나를 둔다. revision 행은 순번 역순을 그대로 지키고(PRD §6-D, W17), 체크포인트 행은 저장 시각 자리에 끼워 넣는다. 체크포인트 행을 고르면 연결된 revision의 과거 구성을 읽기 전용으로 보이고(W18 띠),
  띠 아래에 체크포인트 패널(제목·저장 시각·진행 메모·다음 할 일)을 붙인다. 복원은 띠의 별도 동작이다(W20). 웹 링크는 그 revision의 구성으로 참조한다(0002).
  저장이 실패하면 체크포인트를 부분 생성하지 않고 입력을 유지해 다시 시도할 수 있다(PRD §7). 저장은 연결 대상 파일·폴더에 접근하지 않는다.
  과거와 현재, 오류 상태를 색만으로 구분하지 않는다. 화면 규칙은 디자인 세션이 2026-10-15에 확정한 시안(1A·2A·3B)을 따른다.

  Background:
    Given Board "서비스 A"의 revision이 다음과 같다
      | 순번 | 원인            | 구성                                                                     |
      | 1   | created        | Board 이름 "서비스 A", 비어 있음                                               |
      | 2   | addLinkedItems | 최상위에 Bishop 폴더 "backend"(참조 R1, 당시 경로 /dev/api)와 Wing "개발"            |
      | 3   | addWebLink     | "개발" 아래에 웹 링크 "명세"(https://example.com/spec)                            |
      | 4   | addGroup       | 최상위에 Wing "문서"                                                         |
      | 5   | changeURL      | "명세"의 URL이 https://example.com/spec-v2 가 되었다                             |
    And 현재 revision은 순번 5이고 revision 수는 5다
    And "서비스 A"에 체크포인트가 없다
    And 주입 시계는 오늘 오후 3시 5분이다
    And "서비스 A"의 현재 구성을 보고 있다

  # ── 진입 ─────────────────────────────────────────────

  Scenario: 파일 메뉴 '체크포인트 저장…'을 고르면 현재 revision을 고정한 저장 시트가 열린다
    When 파일 메뉴 '체크포인트 저장…'을 실행한다
    Then "체크포인트 저장" 시트가 열린다
    And 시트의 부제는 "현재 구성 · #5 · " 순번 5의 기록 시각 "기록"이다
    And '제목' 입력 칸이 비어 있고 안내 문구 "예: 인증 리팩토링 1차 완료"가 보이며 초점이 그 칸에 있다
    And '진행 메모'와 '다음 할 일' 입력 영역이 비어 있다
    And 시트에는 안내 "저장한 체크포인트는 고칠 수 없습니다. 고치려면 같은 구성에 새로 저장합니다."가 있다
    And 시트에는 '취소'와 '저장' 버튼이 있고 '저장'은 꺼져 있다
    And revision 수는 5 그대로이고 체크포인트는 없다

  Scenario: 파일 메뉴 '체크포인트 저장…'은 '상태 새로고침' 뒤 구분선 다음에 홀로 있고 '이 구성으로 복원…' 앞이며 단축키가 없다
    Then 파일 메뉴에서 '상태 새로고침' 다음은 구분선, 그다음은 '체크포인트 저장…' 하나뿐이고, 그다음 구분선 뒤에 '이 구성으로 복원…'이 온다
    And '체크포인트 저장…'에는 단축키가 없다

  Scenario: 툴바의 깃발 버튼은 파일 메뉴와 같은 시트를 연다
    Then 툴바에 기호 "flag"와 도움말 '체크포인트 저장'을 가진 버튼이 'Wing 추가' 버튼 오른쪽, 이력 버튼 왼쪽에 있다
    When 툴바의 '체크포인트 저장' 버튼을 누른다
    Then "체크포인트 저장" 시트가 열리고 부제는 "현재 구성 · #5 · " 순번 5의 기록 시각 "기록"이다

  Scenario Outline: '체크포인트 저장…'과 툴바 버튼은 편집할 수 있는 현재 구성을 볼 때만 켜진다
    Given <상태>
    Then 파일 메뉴 '체크포인트 저장…'은 <켜짐>이고 툴바 '체크포인트 저장' 버튼도 <켜짐>이다

    Examples:
      | 상태                                               | 켜짐 |
      | 현재 구성을 보고 있다                                   | 켜짐 |
      | 이력 탭에서 순번 4 revision을 골라 과거 구성을 보고 있다        | 꺼짐 |
      | 순번 4와 현재 구성을 비교하고 있다                          | 꺼짐 |
      | "서비스 A"가 보관되어 있다                                | 꺼짐 |
      | 고른 Board가 없다                                      | 꺼짐 |
      | 현재 구성을 읽지 못해 빈 트리 대신 오류를 보이고 있다               | 꺼짐 |
      | 'Board 만들기' 시트가 열려 있다                            | 꺼짐 |
      | "체크포인트 저장" 시트가 열려 있다                           | 꺼짐 |

  Scenario: 시트를 열 때 현재 revision 정보를 읽지 못하면 시트를 열지 않고 알린다
    Given 저장소가 다음 읽기에서 실패하도록 주입되어 있다
    When 파일 메뉴 '체크포인트 저장…'을 실행한다
    Then 시트는 열리지 않고 읽지 못했다는 안내가 보인다
    And 현재 구성 보기는 그대로이고 revision 수는 5, 체크포인트는 없다

  # ── 시트 ─────────────────────────────────────────────

  Scenario: 제목이 공백뿐이면 '저장'이 꺼지고 Return으로도 저장하지 않는다
    Given "체크포인트 저장" 시트가 열려 있다
    When '제목' 입력 칸에 "   "를 넣는다
    Then '저장' 버튼은 꺼져 있다
    When '제목' 입력 칸에서 Return 키를 누른다
    Then 시트는 열린 채이고 체크포인트는 없다

  Scenario: 제목의 앞뒤 공백은 정리하고 진행 메모·다음 할 일은 줄바꿈까지 입력한 그대로 저장한다
    Given "체크포인트 저장" 시트가 열려 있다
    When '제목'에 "  인증 1차  ", '진행 메모'에 "로그인 완료\n토큰 갱신 남음", '다음 할 일'에 "  갱신 구현 "을 넣고 '저장'을 누른다
    Then 체크포인트의 제목은 "인증 1차", 진행 메모는 "로그인 완료\n토큰 갱신 남음", 다음 할 일은 "  갱신 구현 "이다

  Scenario: 진행 메모와 다음 할 일은 비워 두어도 저장된다
    Given "체크포인트 저장" 시트가 열려 있다
    When '제목'에 "빈 메모"만 넣고 '저장'을 누른다
    Then 순번 5에 제목 "빈 메모", 진행 메모 "", 다음 할 일 ""인 체크포인트가 하나 있다

  @A10
  Scenario: 입력 중에는 revision이 생기지 않고 체크포인트도 아직 없다
    Given "체크포인트 저장" 시트가 열려 있다
    When '제목'에 "작성 중", '진행 메모'에 "아직 저장 전"을 넣는다
    Then revision 수는 5, 현재 revision은 순번 5 그대로이고 체크포인트는 없다

  Scenario: '취소'하면 아무것도 저장하지 않고 입력을 버린다
    Given "체크포인트 저장" 시트가 열려 있다
    When '제목'에 "버릴 제목", '진행 메모'에 "버릴 메모"를 넣고 '취소'를 누른다
    Then 시트가 닫히고 체크포인트는 없으며 revision 수는 5 그대로다
    And 가운데 영역은 "서비스 A"의 현재 구성이고 과거 구성 띠가 없다
    When 파일 메뉴 '체크포인트 저장…'을 다시 실행한다
    Then '제목'·'진행 메모'·'다음 할 일'은 모두 비어 있다

  Scenario: 시트의 키보드와 접근성: 제목 칸의 Return은 '저장', 메모 칸의 Return은 줄바꿈, Esc는 '취소'다
    Given "체크포인트 저장" 시트가 열려 있고 '제목'에 "키보드"가 들어 있다
    Then '저장'이 기본 버튼이고 '제목' 입력 칸에서 Return 키는 '저장'과 같다
    And '진행 메모'·'다음 할 일' 입력 영역에서 Return 키는 줄바꿈을 넣고 저장하지 않는다
    And Esc 키는 '취소'와 같다
    And VoiceOver는 시트 제목, 부제, '제목' 입력 칸, '진행 메모', '다음 할 일', 안내를 차례로 읽는다
    And 시트가 열려 있는 동안 파일 메뉴 '체크포인트 저장…'과 툴바 버튼은 시트를 다시 열지 않는다

  Scenario: 시트가 열린 동안 구성 편집과 Board 상태 변경 명령은 동작하지 않는다
    Given "체크포인트 저장" 시트가 열려 있다
    Then 편집 메뉴의 '이름 변경…'·'URL 변경…'·'위로 이동'·'아래로 이동'·'이동…'·'제거…'는 꺼져 있다
    And 파일 메뉴의 'Bishop 추가…'·'Wing 추가…'·'웹 링크 추가…'·'연결 대상 변경…'·'Board 이름 변경…'·'Board 보관'·'이 구성으로 복원…'·'이 구성으로 새 Board 만들기…'는 꺼져 있다
    And ⌘N(Board 만들기)과 Delete 키, 드래그 앤 드롭은 아무것도 바꾸지 않는다
    And 파일 메뉴 '다시 선택…'은 꺼져 있다(파일 선택 창을 시트 위에 띄우지 않는다)
    And 파일 메뉴 '열기'·'Finder에서 보기'·'상태 새로고침'과 보기 메뉴의 '이력 보기'·'인스펙터 보기/가리기'는 시트를 열기 전과 같은 상태다
    When 시트를 '취소'로 닫는다
    Then 편집 메뉴와 파일 메뉴의 명령은 시트를 열기 전과 같은 상태로 돌아온다

  Scenario: 저장 중에는 확정을 한 번만 받는다
    Given "체크포인트 저장" 시트가 열려 있고 '제목'에 "한 번만"이 들어 있다
    When '저장'을 누르고, 저장이 끝나기 전에 다시 '저장'을 누른다
    Then 저장 중에는 '저장'과 '취소'가 꺼져 있다
    And 순번 5에 제목 "한 번만"인 체크포인트가 하나만 생긴다

  # ── 저장 ─────────────────────────────────────────────

  @A10
  Scenario: '저장'을 확정하면 고정한 revision에 체크포인트가 붙고 revision은 늘지 않는다
    Given "체크포인트 저장" 시트가 열려 있다
    When '제목'에 "인증 1차", '진행 메모'에 "로그인 완료", '다음 할 일'에 "토큰 갱신"을 넣고 '저장'을 누른다
    Then 저장이 성공한 뒤 시트가 닫힌다
    And 순번 5에 제목 "인증 1차", 진행 메모 "로그인 완료", 다음 할 일 "토큰 갱신"인 체크포인트가 있고 저장 시각은 주입 시계의 오후 3시 5분이다
    And revision 수는 5, 현재 revision은 순번 5 그대로다
    And 가운데 영역은 "서비스 A"의 현재 구성이고 과거 구성 띠가 없으며 편집 명령은 다시 켜진다
    And 이력 탭을 열면 '현재 구성' 행이 골라져 있고 오늘 구역 맨 위에 체크포인트 "인증 1차" 행이 있다

  @A10
  Scenario: 같은 revision에 체크포인트를 여러 개 저장할 수 있고 최신이 위에 온다
    Given 순번 5에 제목 "1차"인 체크포인트를 오후 3시 5분에 저장했다
    And 주입 시계가 오후 3시 20분이다
    When "체크포인트 저장" 시트를 열어 '제목'에 "2차"를 넣고 '저장'을 누른다
    Then 순번 5에 체크포인트 "1차"와 "2차"가 서로 다른 ID로 있고 revision 수는 5 그대로다
    And 이력 탭에서 "2차" 행이 "1차" 행 위에 있고 둘 다 순번 5 revision 행 위에 있다

  @A10
  Scenario: 저장한 체크포인트는 그 뒤 구성이 바뀌어도 원래 revision에 그대로 남는다
    Given 순번 5에 제목 "1차"인 체크포인트를 저장했다
    When "서비스 A"의 현재 구성에 Wing "임시"를 더한다
    Then revision 수는 6이고 현재 revision은 순번 6이다
    And 체크포인트 "1차"는 순번 5에 그대로 붙어 있고 제목·진행 메모·다음 할 일·저장 시각이 바뀌지 않았다
    And 순번 6에는 체크포인트가 없다

  Scenario: 저장이 실패하면 체크포인트가 생기지 않고 시트는 입력을 유지한 채 저장 실패를 알린다
    Given 저장소가 다음 저장에서 실패하도록 주입되어 있다
    And "체크포인트 저장" 시트가 열려 있다
    When '제목'에 "실패 뒤", '진행 메모'에 "메모 유지", '다음 할 일'에 "할 일 유지"를 넣고 '저장'을 누른다
    Then 체크포인트는 없고 revision 수는 5 그대로다
    And 시트는 열린 채 제목 "실패 뒤", 진행 메모 "메모 유지", 다음 할 일 "할 일 유지"를 유지한다
    And 버튼 위에 기호 "exclamationmark.triangle"과 "저장하지 못했습니다. 입력한 내용은 그대로 있으니 다시 시도하세요."가 보인다
    When 저장소가 정상으로 돌아온 뒤 '저장'을 다시 누른다
    Then 순번 5에 제목 "실패 뒤"인 체크포인트가 하나 있고 시트가 닫힌다

  Scenario: 체크포인트 저장은 연결 대상 파일·폴더를 읽거나 바꾸지 않는다
    Given "체크포인트 저장" 시트가 열려 있다
    When '제목'에 "파일 접근 없음"을 넣고 '저장'을 누른다
    Then 시트를 연 때부터 저장이 끝날 때까지 파일 시스템 접근, 접근 정보 해석, 연결 대상 열기는 한 번도 일어나지 않는다
    And /dev/api 대상의 내용은 그대로다

  # ── 이력 탭 ───────────────────────────────────────────

  Scenario: 체크포인트 행은 깃발 기호와 제목, 아래 줄 '체크포인트 · #n · 시각'으로 보이고 VoiceOver가 한 요소로 읽는다
    Given 순번 5에 제목 "인증 1차"인 체크포인트를 오후 3시 5분에 저장했다
    When 이력 탭을 연다
    Then 체크포인트 "인증 1차" 행은 기호 "flag.fill"과 제목 "인증 1차", 아래 줄 "체크포인트 · #5 · " 오후 3시 5분으로 보인다
    And 그 행의 VoiceOver 라벨은 "체크포인트, 인증 1차, #5 구성, " 오후 3시 5분 " 저장"이다
    And 그 행의 접근성 식별자는 "checkpoint-row-인증 1차"다

  Scenario: 체크포인트 행은 저장 시각 자리에 끼어들고 날짜 구역은 행 자신의 시각을 따른다
    Given 순번 1부터 5까지의 기록 시각은 모두 어제다
    And 이력 탭에서 순번 3 revision을 골랐다가 현재 구성으로 돌아왔다
    And 순번 5에 제목 "어제 메모"인 체크포인트를 어제 오후 6시에 저장했다
    And 순번 5에 제목 "오늘 메모"인 체크포인트를 오늘 오후 3시 5분에 저장했다
    When 이력 탭을 연다
    Then 오늘 구역에는 체크포인트 "오늘 메모" 행 하나뿐이다
    And 어제 구역의 순서는 체크포인트 "어제 메모", 순번 5, 순번 4, 순번 3, 순번 2, 순번 1이다

  Scenario: 오래된 revision에 나중에 저장한 체크포인트는 그 revision 행보다 위, 자기 시각 자리에 온다
    Given 순번 1부터 5까지의 기록 시각은 모두 어제다
    And 순번 5에 체크포인트가 없고 현재 구성을 보고 있다
    And 주입 시계가 오늘 오후 3시 5분일 때 순번 5에 제목 "오늘 저장"인 체크포인트를 저장했다
    When 이력 탭을 연다
    Then 체크포인트 "오늘 저장" 행은 오늘 구역에 있고 순번 5 행은 어제 구역에 있다

  Scenario: revision 행에는 체크포인트 수를 표시하지 않는다
    Given 순번 5에 제목 "1차"와 "2차"인 체크포인트를 저장했다
    When 이력 탭을 연다
    Then 순번 5 revision 행에는 깃발 기호나 숫자가 없고 원인 문구와 '#5 · 시각'만 있다

  Scenario: 더 오래된 묶음을 불러와도 체크포인트 행은 한 번만, 자기 자리에 남는다
    Given "서비스 A"의 revision 수가 60이고 현재 revision은 순번 60이며 기록 시각은 순번 순서대로 늘어난다
    And 순번 60에 제목 "최신"인 체크포인트를 저장했다
    And 순번 2에 붙은 제목 "오래된 revision의 메모"인 체크포인트가 순번 59와 순번 60 사이 시각에 저장되어 있다
    And 순번 2에 붙은 제목 "당시 메모"인 체크포인트가 순번 2와 순번 3 사이 시각에 저장되어 있다
    When 이력 탭을 연다
    Then 불러온 revision 행은 순번 60부터 11까지이고 체크포인트 "최신" 행은 맨 위, "오래된 revision의 메모" 행은 순번 60 행 아래·순번 59 행 위에 있다
    And "당시 메모" 행은 목록 맨 아래(순번 11 행 아래)에 보인다
    When 목록 끝까지 스크롤한다
    Then 마지막 행이 체크포인트 행이어도 다음 묶음을 불러온다
    And "당시 메모" 행은 순번 3 행 아래·순번 2 행 위로 옮겨져 한 번만 있고, "오래된 revision의 메모" 행도 한 번만 있다
    And 순번 1부터 60까지의 revision 행이 모두 한 번씩 있다

  Scenario: 이력 탭이 열린 채 체크포인트를 저장하면 행이 더해지고 선택은 '현재 구성'에 남는다
    Given 이력 탭이 열려 있고 '현재 구성' 행이 골라져 있다
    When "체크포인트 저장" 시트를 열어 '제목'에 "열린 채 저장"을 넣고 '저장'을 누른다
    Then 이력 탭 맨 위에 체크포인트 "열린 채 저장" 행이 생기고 '현재 구성' 행이 여전히 골라져 있다
    And 가운데 영역은 현재 구성이고 과거 구성 띠가 없다

  Scenario Outline: 이력 행 병합은 순수 함수다: revision 행은 순번 역순 그대로, 체크포인트 행은 기록 시각이 저장 시각 이하인 첫 revision 행 앞
    Given revision 목록 <revision들>과 체크포인트 목록 <체크포인트들>이 있다(t1 < t1.5 < t2 < t3 < t4, ID 문자열 순은 c1 < c2)
    When 이력 행으로 병합한다
    Then 행 순서는 <결과>이고 입력 목록은 바뀌지 않으며 같은 입력이면 같은 결과다
    And revision 행끼리의 순서는 순번 역순이고, 체크포인트 행은 위에서부터 기록 시각이 자기 저장 시각 이하인 첫 revision 행 바로 앞(없으면 맨 아래)에 있으며, 같은 자리의 체크포인트끼리는 저장 시각 역순, 같으면 연결 revision 순번 역순, 같으면 ID 문자열 순이다

    Examples:
      | revision들                       | 체크포인트들                               | 결과                      |
      | 비어 있음                          | 비어 있음                                 | 비어 있음                   |
      | #1(t1), #2(t2)                   | 비어 있음                                 | #2, #1                   |
      | #1(t1), #2(t2)                   | c1(#2, t3)                               | c1, #2, #1               |
      | #1(t1), #2(t2), #3(t3)           | c1(#1, t4)                               | c1, #3, #2, #1           |
      | #1(t1), #2(t2)                   | c1(#2, t2)                               | c1, #2, #1               |
      | #1(t1), #2(t2)                   | c1(#1, t1.5)                             | #2, c1, #1               |
      | #1(t1), #2(t2)                   | c1(#2, t3), c2(#2, t4)                   | c2, c1, #2, #1           |
      | #1(t1), #2(t2)                   | c1(#1, t3), c2(#2, t3)                   | c2, c1, #2, #1           |
      | #1(t1), #2(t2)                   | c1(#2, t3), c2(#2, t3)                   | c1, c2, #2, #1           |
      | #2(t2)                           | c1(#1, t3)                               | c1, #2                   |
      | #2(t2)                           | c1(#1, t1)                               | #2, c1                   |
      | 비어 있음                          | c1(#1, t1)                               | c1                       |
      | #1(t2), #2(t1)                   | 비어 있음                                 | #2, #1                   |
      | #1(t2), #2(t1)                   | c1(#1, t1.5), c2(#2, t3)                 | c2, c1, #2, #1           |
      | #1(t2), #2(t1)                   | c1(#1, t4), c2(#2, t1)                   | c1, c2, #2, #1           |

  # ── 조회 ─────────────────────────────────────────────

  @A10
  Scenario: 체크포인트 행을 고르면 연결된 revision의 과거 구성과 띠 아래 체크포인트 패널이 보인다
    Given 순번 3에 제목 "명세 확정", 진행 메모 "명세 링크 정리함", 다음 할 일 "문서 Wing 만들기"인 체크포인트를 오후 3시 5분에 저장했다
    And 이력 탭이 열려 있다
    When 체크포인트 "명세 확정" 행을 고른다
    Then 가운데 영역은 "서비스 A"의 순번 3 구성이고 과거 구성 띠에 "#3 · " 순번 3의 기록 시각 " 기록"이 보인다
    And 편집 메뉴 명령·툴바 추가 버튼·드래그 앤 드롭·Delete 키는 꺼져 있다
    And 띠 바로 아래 체크포인트 패널에 기호 "flag.fill", 제목 "명세 확정", "오후 3:05 저장"을 포함한 저장 시각, 접기 버튼이 있다
    And 패널에 '진행 메모' 열 "명세 링크 정리함"과 '다음 할 일' 열 "문서 Wing 만들기"가 있고 본문 글은 선택할 수 있다
    And 체크포인트 "명세 확정" 행이 골라져 있고 순번 3 revision 행과 '현재 구성' 행은 골라져 있지 않다
    And 구성에서 "명세"를 고르면 인스펙터 '고른 항목' 카드가 당시 URL https://example.com/spec 를 보인다
    And revision 수는 5 그대로다

  @A10
  Scenario: 현재 revision에 붙은 체크포인트를 골라도 과거 구성 보기로 보이고 패널이 붙는다
    Given 순번 5에 제목 "지금 구성"인 체크포인트를 저장했다
    And 이력 탭이 열려 있다
    When 체크포인트 "지금 구성" 행을 고른다
    Then 가운데 영역에 과거 구성 띠 "#5 · " 순번 5의 기록 시각 " 기록"이 보이고 편집 명령은 꺼져 있다
    And 띠 아래 체크포인트 패널에 제목 "지금 구성"이 있다
    And '현재 구성' 행은 골라져 있지 않고 체크포인트 "지금 구성" 행이 골라져 있다
    And 파일 메뉴 '체크포인트 저장…'은 꺼져 있다

  Scenario: 패널은 비어 있는 열을 빼고, 둘 다 비면 제목 줄만 보인다
    Given 순번 5에 제목 "메모만", 진행 메모 "진행 중", 다음 할 일 ""인 체크포인트를 저장했다
    And 순번 5에 제목 "제목만", 진행 메모 "", 다음 할 일 "   "인 체크포인트를 저장했다
    And 이력 탭이 열려 있다
    When 체크포인트 "메모만" 행을 고른다
    Then 패널에는 '진행 메모' 열 "진행 중"만 있고 '다음 할 일' 열이 없다
    When 체크포인트 "제목만" 행을 고른다
    Then 패널에는 제목 줄과 저장 시각만 있고 '진행 메모'·'다음 할 일' 열이 없다

  Scenario: 패널 접기는 본문만 숨기는 화면 상태이고 다른 체크포인트를 고르면 펴진다
    Given 순번 5에 제목 "첫째", 진행 메모 "첫째 메모"인 체크포인트와 제목 "둘째", 진행 메모 "둘째 메모"인 체크포인트를 저장했다
    And 이력 탭에서 체크포인트 "첫째" 행을 골랐다
    When 패널의 접기 버튼(도움말 '체크포인트 접기')을 누른다
    Then 패널에는 제목 "첫째"와 저장 시각만 보이고 "첫째 메모"는 보이지 않으며 버튼 도움말은 '체크포인트 펴기'다
    And revision 수는 5 그대로이고 체크포인트도 그대로다
    When 체크포인트 "둘째" 행을 고른다
    Then 패널은 펴진 채 제목 "둘째"와 "둘째 메모"를 보인다
    And 접기 버튼은 키보드로 초점을 받아 Space로 누를 수 있다

  Scenario: 체크포인트를 보다가 같은 revision 행을 고르면 패널만 사라지고 구성은 그대로다
    Given 순번 3에 제목 "명세 확정"인 체크포인트를 저장했다
    And 이력 탭에서 체크포인트 "명세 확정" 행을 골랐다
    When 순번 3 revision 행을 고른다
    Then 가운데 영역은 여전히 순번 3 구성이고 과거 구성 띠가 보이며 체크포인트 패널은 없다
    And 순번 3 revision 행이 골라져 있고 체크포인트 행은 골라져 있지 않다

  Scenario: 체크포인트를 보다가 현재로 돌아가면 패널과 띠가 사라진다
    Given 순번 3에 제목 "명세 확정"인 체크포인트를 저장했다
    And 이력 탭에서 체크포인트 "명세 확정" 행을 골랐다
    When 띠의 '현재로 돌아가기'를 누른다
    Then 가운데 영역은 현재 구성이고 과거 구성 띠와 체크포인트 패널이 없으며 '현재 구성' 행이 골라져 있다
    When 체크포인트 "명세 확정" 행을 다시 고르고 이력 탭의 '현재 구성' 행을 고른다
    Then 가운데 영역은 현재 구성이고 체크포인트 패널이 없다

  Scenario: 체크포인트를 보며 '현재와 비교'를 열면 패널은 보이지 않고 닫으면 돌아온다
    Given 순번 3에 제목 "명세 확정"인 체크포인트와 순번 4에 제목 "문서 추가"인 체크포인트를 저장했다
    And 이력 탭에서 체크포인트 "명세 확정" 행을 골랐다
    When 띠의 '현재와 비교'를 누른다
    Then 순번 3과 현재 구성의 비교가 열리고 체크포인트 패널은 보이지 않는다
    When 비교를 닫는다
    Then 가운데 영역은 순번 3 구성이고 띠 아래 체크포인트 패널에 제목 "명세 확정"이 보이며 체크포인트 행이 여전히 골라져 있다
    When 띠의 '현재와 비교'를 다시 누르고, 비교 중에 체크포인트 "문서 추가" 행을 고른다
    Then 비교가 닫히고 가운데 영역은 순번 4 구성이며 띠 아래 체크포인트 패널에 제목 "문서 추가"가 보인다

  Scenario: 체크포인트 행의 오른쪽 클릭 '이 기록과 비교'는 그 revision 행과 같다
    Given 순번 3에 제목 "명세 확정"인 체크포인트를 저장했다
    And 이력 탭이 열려 있고 현재 구성을 보고 있다
    When 체크포인트 "명세 확정" 행에서 '이 기록과 비교'를 고른다
    Then 이전 = 순번 3, 이후 = 현재 구성인 비교가 열린다
    When 비교를 닫고 순번 3 revision 행을 고른다
    Then 체크포인트 "명세 확정" 행의 '이 기록과 비교'는 꺼져 있다
    When 체크포인트 "명세 확정" 행을 고른다
    Then 순번 3 revision 행의 '이 기록과 비교'는 꺼져 있고 순번 4 revision 행의 '이 기록과 비교'는 켜져 있다

  Scenario: 체크포인트 보기에서 복원은 띠의 별도 동작이고 체크포인트는 그대로 남는다
    Given 순번 3에 제목 "명세 확정"인 체크포인트를 저장했다
    And 이력 탭에서 체크포인트 "명세 확정" 행을 골랐다
    When 띠의 '이 구성으로…' 메뉴에서 '복원…'을 고르고 '복원'을 확정한다
    Then revision 수는 6이고 순번 6의 원인은 순번 3에서 복원이다
    And 체크포인트 "명세 확정"은 순번 3에 그대로 붙어 있고 순번 6에는 체크포인트가 없다
    And 가운데 영역은 현재 구성이고 체크포인트 패널이 없다

  Scenario: 체크포인트의 revision 구성을 읽을 수 없으면 선택을 바꾸지 않고 알린다
    Given 순번 3에 제목 "명세 확정"인 체크포인트를 저장했다
    And 순번 3 revision의 구성 JSON이 손상되어 디코딩할 수 없다
    And 이력 탭이 열려 있고 현재 구성을 보고 있다
    When 체크포인트 "명세 확정" 행을 고른다
    Then 구성을 읽지 못했다는 안내가 보이고 가운데 영역은 현재 구성이며 체크포인트 패널이 없다
    And '현재 구성' 행이 골라져 있고 저장된 기록은 지우거나 고치지 않는다

  Scenario: 아이콘 보기에서도 체크포인트를 고르면 같은 띠와 패널이 보인다
    Given 순번 3에 제목 "명세 확정"인 체크포인트를 저장했다
    And 아이콘 보기로 보고 있고 이력 탭이 열려 있다
    When 체크포인트 "명세 확정" 행을 고른다
    Then 아이콘 보기 위에 과거 구성 띠 "#3"과 체크포인트 패널 "명세 확정"이 보이고 편집 명령은 꺼져 있다

  Scenario: 체크포인트가 가리키는 웹 링크는 그 revision의 구성으로 보인다
    Given 순번 3에 제목 "명세 확정"인 체크포인트를 저장했다
    And 이력 탭에서 체크포인트 "명세 확정" 행을 골랐다
    When 구성에서 웹 링크 "명세"를 고른다
    Then '고른 항목' 카드의 URL은 https://example.com/spec 이고 현재 구성의 https://example.com/spec-v2 가 아니다
    And 체크포인트 레코드에는 URL이 따로 저장되어 있지 않다

  # ── 서비스 경계 ─────────────────────────────────────────

  Scenario Outline: 서비스는 저장 요청을 결정표 checkpoint_request_outcome으로 판정하고 첫 번째로 맞는 규칙의 outcome을 돌려준다
    Given title이 <title>, project가 <project>, board_state가 <board_state>, revision이 <revision>, revision_currency가 <revision_currency>다
    When 서비스에 체크포인트 저장을 요청한다
    Then outcome은 <outcome>이고 체크포인트는 outcome이 saved일 때만 하나 늘어나며 revision 수와 현재 revision은 늘 그대로다

    Examples:
      | title | project   | board_state | revision    | revision_currency | outcome                      |
      | blank | found     | active      | found       | current           | rejected_blank_title         |
      | blank | not_found | archived    | other_board | not_current       | rejected_blank_title         |
      | valid | not_found | active      | found       | current           | rejected_project_not_found   |
      | valid | found     | archived    | found       | current           | rejected_archived            |
      | valid | found     | archived    | not_found   | not_current       | rejected_archived            |
      | valid | found     | active      | not_found   | current           | rejected_revision_not_found  |
      | valid | found     | active      | other_board | not_current       | rejected_revision_not_found  |
      | valid | found     | active      | found       | current           | saved                        |
      | valid | found     | active      | found       | not_current       | saved                        |

  @A10
  Scenario: 저장된 체크포인트 레코드는 고정한 revision, 정리한 제목, 입력 그대로의 메모, 주입 시계의 시각, 빈 첨부를 가진다
    When 서비스에 "서비스 A" 순번 5로 제목 "  인증 1차 ", 진행 메모 "로그인 완료\n", 다음 할 일 "토큰 갱신" 저장을 요청한다
    Then outcome은 saved이고 순번 5의 체크포인트는 제목 "인증 1차", 진행 메모 "로그인 완료\n", 다음 할 일 "토큰 갱신", 저장 시각은 주입 시계, 첨부는 비어 있다
    And revision 수는 5, 현재 revision은 순번 5 그대로다
    And 같은 요청을 다시 보내면 다른 ID의 두 번째 체크포인트가 순번 5에 생긴다

  Scenario: 체크포인트는 한 저장 단위로 커밋되고 실패하면 아무것도 남지 않는다
    Given 저장소가 다음 저장에서 실패하도록 주입되어 있다
    When 서비스에 "서비스 A" 순번 5로 제목 "실패" 저장을 요청한다
    Then 결과는 저장 실패이고 저장소의 체크포인트 수는 0, "서비스 A"의 revision 수는 5, 현재 revision은 순번 5 그대로다
    When 저장소가 정상으로 돌아온 뒤 같은 요청을 보낸다
    Then outcome은 saved이고 체크포인트 수는 1이다

  Scenario: 없는 revision이나 다른 Board의 revision에는 붙이지 않는다
    Given Board "서비스 Z"의 revision X가 있다
    When 서비스에 "서비스 A"의 revision으로 X 또는 없는 ID를 주어 저장을 요청한다
    Then outcome은 rejected_revision_not_found이고 두 Board 어디에도 체크포인트가 없다

  Scenario: 보관된 Board에는 체크포인트를 저장하지 않는다
    Given "서비스 A"가 보관되어 있다
    When 서비스에 "서비스 A" 순번 5로 제목 "보관 중" 저장을 요청한다
    Then outcome은 rejected_archived이고 체크포인트는 없다
    When "서비스 A"의 보관을 해제한 뒤 같은 요청을 보낸다
    Then outcome은 saved이고 순번 5에 체크포인트가 하나 있다
```

### .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/W22.decision.yaml

| rule_id | title | project | board_state | revision | revision_currency | outcome |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | blank | (blank) | (blank) | (blank) | (blank) | rejected_blank_title |
| R2 | (blank) | not_found | (blank) | (blank) | (blank) | rejected_project_not_found |
| R3 | (blank) | (blank) | archived | (blank) | (blank) | rejected_archived |
| R4 | (blank) | (blank) | (blank) | [not_found, other_board] | (blank) | rejected_revision_not_found |
| R5 | (blank) | (blank) | (blank) | found | (blank) | saved |

셀 맵

| title | project | board_state | revision | revision_currency | rule_id |
| --- | --- | --- | --- | --- | --- |
| valid | found | active | found | current | R5 |
| valid | found | active | found | not_current | R5 |
| valid | found | active | not_found | current | R4 |
| valid | found | active | not_found | not_current | R4 |
| valid | found | active | other_board | current | R4 |
| valid | found | active | other_board | not_current | R4 |
| valid | found | archived | found | current | R3 |
| valid | found | archived | found | not_current | R3 |
| valid | found | archived | not_found | current | R3 |
| valid | found | archived | not_found | not_current | R3 |
| valid | found | archived | other_board | current | R3 |
| valid | found | archived | other_board | not_current | R3 |
| valid | not_found | active | found | current | R2 |
| valid | not_found | active | found | not_current | R2 |
| valid | not_found | active | not_found | current | R2 |
| valid | not_found | active | not_found | not_current | R2 |
| valid | not_found | active | other_board | current | R2 |
| valid | not_found | active | other_board | not_current | R2 |
| valid | not_found | archived | found | current | R2 |
| valid | not_found | archived | found | not_current | R2 |
| valid | not_found | archived | not_found | current | R2 |
| valid | not_found | archived | not_found | not_current | R2 |
| valid | not_found | archived | other_board | current | R2 |
| valid | not_found | archived | other_board | not_current | R2 |
| blank | found | active | found | current | R1 |
| blank | found | active | found | not_current | R1 |
| blank | found | active | not_found | current | R1 |
| blank | found | active | not_found | not_current | R1 |
| blank | found | active | other_board | current | R1 |
| blank | found | active | other_board | not_current | R1 |
| blank | found | archived | found | current | R1 |
| blank | found | archived | found | not_current | R1 |
| blank | found | archived | not_found | current | R1 |
| blank | found | archived | not_found | not_current | R1 |
| blank | found | archived | other_board | current | R1 |
| blank | found | archived | other_board | not_current | R1 |
| blank | not_found | active | found | current | R1 |
| blank | not_found | active | found | not_current | R1 |
| blank | not_found | active | not_found | current | R1 |
| blank | not_found | active | not_found | not_current | R1 |
| blank | not_found | active | other_board | current | R1 |
| blank | not_found | active | other_board | not_current | R1 |
| blank | not_found | archived | found | current | R1 |
| blank | not_found | archived | found | not_current | R1 |
| blank | not_found | archived | not_found | current | R1 |
| blank | not_found | archived | not_found | not_current | R1 |
| blank | not_found | archived | other_board | current | R1 |
| blank | not_found | archived | other_board | not_current | R1 |

### .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/W22.decision.vectors.yaml

벡터 파일 (§4에 반영)

## 3. Test obligations

| obligation_id | kind | description | acceptance_refs | source |
| --- | --- | --- | --- | --- |
| W22-file-menu-opens-sheet | scenario | 파일 메뉴 '체크포인트 저장…'이 "체크포인트 저장" 시트를 열고 부제(현재 구성 · #n · 기록 시각)·빈 제목 칸(안내·초점)·빈 메모 영역·안내·'취소'/'저장'(꺼짐)을 보이며 아무것도 저장하지 않는다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#파일 메뉴 '체크포인트 저장…'을 고르면 현재 revision을 고정한 저장 시트가 열린다 |
| W22-file-menu-placement | scenario | '체크포인트 저장…'은 '상태 새로고침' 뒤 구분선 다음 단독 그룹, '이 구성으로 복원…' 앞이고 단축키가 없다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#파일 메뉴 '체크포인트 저장…'은 '상태 새로고침' 뒤 구분선 다음에 홀로 있고 '이 구성으로 복원…' 앞이며 단축키가 없다 |
| W22-toolbar-opens-sheet | scenario | 툴바 flag 버튼(도움말 '체크포인트 저장', 'Wing 추가' 오른쪽·이력 버튼 왼쪽)이 같은 시트를 연다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#툴바의 깃발 버튼은 파일 메뉴와 같은 시트를 연다 |
| W22-entry-enablement | scenario | 파일 메뉴 항목과 툴바 버튼의 켜짐 조건 여덟 가지(현재/과거/비교 중/보관/Board 없음/현재 구성 읽기 실패/다른 시트/이 시트) |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#'체크포인트 저장…'과 툴바 버튼은 편집할 수 있는 현재 구성을 볼 때만 켜진다 |
| W22-open-read-failure | scenario | 시트를 열 때 현재 revision 정보를 읽지 못하면 시트를 열지 않고 안내하며 아무것도 바꾸지 않는다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#시트를 열 때 현재 revision 정보를 읽지 못하면 시트를 열지 않고 알린다 |
| W22-blank-title-disables-save | scenario | 공백뿐인 제목이면 '저장'이 꺼지고 Return으로도 저장하지 않는다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#제목이 공백뿐이면 '저장'이 꺼지고 Return으로도 저장하지 않는다 |
| W22-title-trimmed-notes-verbatim | scenario | 제목은 앞뒤 공백을 정리하고 진행 메모·다음 할 일은 줄바꿈까지 입력 그대로 저장한다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#제목의 앞뒤 공백은 정리하고 진행 메모·다음 할 일은 줄바꿈까지 입력한 그대로 저장한다 |
| W22-optional-notes-empty | scenario | 진행 메모·다음 할 일이 비어 있어도 저장된다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#진행 메모와 다음 할 일은 비워 두어도 저장된다 |
| W22-no-revision-while-typing | scenario | 입력 중에는 revision 수·현재 revision이 그대로이고 체크포인트도 아직 없다 | A10 | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#입력 중에는 revision이 생기지 않고 체크포인트도 아직 없다 |
| W22-cancel-discards-input | scenario | '취소'는 아무것도 저장하지 않고 입력을 버리며 다시 열면 비어 있다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#'취소'하면 아무것도 저장하지 않고 입력을 버린다 |
| W22-sheet-keyboard-accessibility | scenario | 제목 칸 Return은 '저장', 메모 영역 Return은 줄바꿈, Esc는 '취소', VoiceOver 순서, 열린 동안 재진입 없음 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#시트의 키보드와 접근성: 제목 칸의 Return은 '저장', 메모 칸의 Return은 줄바꿈, Esc는 '취소'다 |
| W22-sheet-blocks-editing | scenario | 시트가 열린 동안 편집 메뉴·파일 메뉴의 구성 편집·Board 상태 변경 명령·'다시 선택…'과 ⌘N·Delete·드롭이 동작하지 않고, 열기·Finder·상태 새로고침·이력 보기는 그대로이며 닫으면 돌아온다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#시트가 열린 동안 구성 편집과 Board 상태 변경 명령은 동작하지 않는다 |
| W22-single-save-while-saving | scenario | 저장 중에는 '저장'·'취소'가 꺼지고 체크포인트는 하나만 생긴다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#저장 중에는 확정을 한 번만 받는다 |
| W22-save-attaches-to-fixed-revision | scenario | 확정 시 고정한 revision에 제목·메모·다음 할 일·주입 시계 시각의 체크포인트가 붙고 revision 수·현재 revision은 그대로이며 화면은 현재 구성에 머물고 이력 탭 맨 위에 행이 생긴다 | A10 | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#'저장'을 확정하면 고정한 revision에 체크포인트가 붙고 revision은 늘지 않는다 |
| W22-multiple-checkpoints-same-revision | scenario | 같은 revision에 체크포인트를 여러 개 저장할 수 있고 서로 다른 ID이며 최신이 위에 온다 | A10 | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#같은 revision에 체크포인트를 여러 개 저장할 수 있고 최신이 위에 온다 |
| W22-checkpoint-immutable-after-edit | scenario | 저장 뒤 구성이 바뀌어 새 revision이 생겨도 체크포인트는 원래 revision에 그대로 남는다 | A10 | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#저장한 체크포인트는 그 뒤 구성이 바뀌어도 원래 revision에 그대로 남는다 |
| W22-save-failure-keeps-input | scenario | 저장 실패 시 체크포인트가 생기지 않고 시트가 입력을 유지한 채 경고 기호와 문구를 보이며 재시도가 된다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#저장이 실패하면 체크포인트가 생기지 않고 시트는 입력을 유지한 채 저장 실패를 알린다 |
| W22-save-no-file-access | scenario | 저장은 파일 시스템 접근·접근 정보 해석·연결 대상 열기를 하지 않고 원본 내용이 그대로다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트 저장은 연결 대상 파일·폴더를 읽거나 바꾸지 않는다 |
| W22-history-row-shape | scenario | 체크포인트 행은 flag.fill+제목, 아래 '체크포인트 · #n · 시각', VoiceOver 라벨, 식별자 checkpoint-row-<제목> |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트 행은 깃발 기호와 제목, 아래 줄 '체크포인트 · #n · 시각'으로 보이고 VoiceOver가 한 요소로 읽는다 |
| W22-history-row-order | scenario | 체크포인트 행은 저장 시각 자리에 끼어들고(어제 저장은 어제 구역, 오늘 저장은 오늘 구역) 날짜 구역은 행 자신의 시각을 따른다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트 행은 저장 시각 자리에 끼어들고 날짜 구역은 행 자신의 시각을 따른다 |
| W22-history-old-revision-new-checkpoint | scenario | 오래된 revision에 나중에 저장한 체크포인트는 자기 시각 자리(오늘 구역)에 오고 revision 행은 어제 구역에 남는다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#오래된 revision에 나중에 저장한 체크포인트는 그 revision 행보다 위, 자기 시각 자리에 온다 |
| W22-history-no-count-on-revision-rows | scenario | revision 행에는 체크포인트 수(flag+숫자)를 표시하지 않는다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#revision 행에는 체크포인트 수를 표시하지 않는다 |
| W22-history-paging-keeps-rows | scenario | 불러온 범위보다 오래된 체크포인트는 첫 묶음에서 맨 아래에 보이고, 마지막 행이 체크포인트 행이어도 다음 묶음을 불러오며, 불러온 뒤 체크포인트 행은 한 번만 자기 자리로 옮겨지고 revision 행이 모두 한 번씩 있다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#더 오래된 묶음을 불러와도 체크포인트 행은 한 번만, 자기 자리에 남는다 |
| W22-history-updates-after-save | scenario | 이력 탭이 열린 채 저장하면 행이 더해지고 선택은 '현재 구성'에 남는다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#이력 탭이 열린 채 체크포인트를 저장하면 행이 더해지고 선택은 '현재 구성'에 남는다 |
| W22-timeline-merge-pure | scenario | Domain 병합은 revision 행을 순번 역순 그대로 두고 체크포인트 행을 기록 시각이 저장 시각 이하인 첫 revision 행 앞(없으면 맨 아래)에 넣으며(같은 자리는 시각 역순·순번 역순·ID 순) 입력을 바꾸지 않고 결정적이다(빈 입력·시계 역행·동시각·연결 행 없는 체크포인트 포함) |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#이력 행 병합은 순수 함수다: revision 행은 순번 역순 그대로, 체크포인트 행은 기록 시각이 저장 시각 이하인 첫 revision 행 앞 |
| W22-select-shows-past-and-panel | scenario | 체크포인트 행을 고르면 연결 revision의 과거 구성(띠·읽기 전용)과 띠 아래 패널(제목·저장 시각·접기·메모 두 열·선택 가능 본문)이 보이고 행 선택이 바뀌며 '고른 항목' 카드가 유지된다 | A10 | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트 행을 고르면 연결된 revision의 과거 구성과 띠 아래 체크포인트 패널이 보인다 |
| W22-select-current-revision-checkpoint | scenario | 현재 revision에 붙은 체크포인트도 과거 모드(띠·편집 꺼짐)와 패널로 보이고 '체크포인트 저장…'은 꺼진다 | A10 | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#현재 revision에 붙은 체크포인트를 골라도 과거 구성 보기로 보이고 패널이 붙는다 |
| W22-panel-omits-empty-columns | scenario | 패널은 비어 있는(공백뿐인) 열을 빼고 둘 다 비면 제목 줄만 보인다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#패널은 비어 있는 열을 빼고, 둘 다 비면 제목 줄만 보인다 |
| W22-panel-collapse | scenario | 접기 버튼은 본문만 숨기는 화면 상태(저장·revision 없음)이고 다른 체크포인트를 고르면 펴지며 키보드로 누를 수 있다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#패널 접기는 본문만 숨기는 화면 상태이고 다른 체크포인트를 고르면 펴진다 |
| W22-switch-to-revision-row | scenario | 체크포인트를 보다가 같은 revision 행을 고르면 패널만 사라지고 구성·띠는 그대로다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트를 보다가 같은 revision 행을 고르면 패널만 사라지고 구성은 그대로다 |
| W22-return-to-current | scenario | 띠 '현재로 돌아가기'와 '현재 구성' 행이 패널·띠를 없애고 현재 구성으로 돌린다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트를 보다가 현재로 돌아가면 패널과 띠가 사라진다 |
| W22-compare-with-current-hides-panel | scenario | 체크포인트를 보며 '현재와 비교'를 열면 패널이 보이지 않고 닫으면 선택·패널이 돌아오며, 비교 중 다른 체크포인트 행을 고르면 비교가 닫히고 그 구성과 패널이 보인다(0027) |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트를 보며 '현재와 비교'를 열면 패널은 보이지 않고 닫으면 돌아온다 |
| W22-compare-record-menu | scenario | 체크포인트 행의 '이 기록과 비교'는 연결 revision 행과 같고 보고 있는 구성이 그 revision이면 꺼진다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트 행의 오른쪽 클릭 '이 기록과 비교'는 그 revision 행과 같다 |
| W22-restore-is-separate | scenario | 체크포인트 보기에서 복원은 띠의 별도 동작이고 복원 revision이 생겨도 체크포인트는 원래 revision에 남는다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트 보기에서 복원은 띠의 별도 동작이고 체크포인트는 그대로 남는다 |
| W22-unreadable-revision-notice | scenario | 연결 revision의 구성을 읽을 수 없으면 선택을 바꾸지 않고 안내하며 기록을 지우거나 고치지 않는다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트의 revision 구성을 읽을 수 없으면 선택을 바꾸지 않고 알린다 |
| W22-icon-view-same-panel | scenario | 아이콘 보기에서도 같은 띠·패널·읽기 전용 규칙이다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#아이콘 보기에서도 체크포인트를 고르면 같은 띠와 패널이 보인다 |
| W22-weblink-from-revision | scenario | 체크포인트가 가리키는 웹 링크는 연결 revision의 URL로 보이고 레코드에 URL이 따로 없다(0002) |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트가 가리키는 웹 링크는 그 revision의 구성으로 보인다 |
| W22-service-outcome-table | scenario | 서비스 판정은 결정표 checkpoint_request_outcome(FIRST)과 같고 saved일 때만 체크포인트가 하나 늘며 revision은 늘 그대로다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#서비스는 저장 요청을 결정표 checkpoint_request_outcome으로 판정하고 첫 번째로 맞는 규칙의 outcome을 돌려준다 |
| W22-service-record-fields | scenario | 저장된 레코드는 고정 revision·정리한 제목·입력 그대로의 메모·주입 시계 시각·빈 첨부를 가지며 revision은 그대로이고 같은 요청을 다시 보내면 다른 ID의 두 번째가 생긴다 | A10 | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#저장된 체크포인트 레코드는 고정한 revision, 정리한 제목, 입력 그대로의 메모, 주입 시계의 시각, 빈 첨부를 가진다 |
| W22-service-atomic-commit | scenario | 저장 실패 주입 시 체크포인트가 남지 않고 revision 수·현재 revision이 그대로이며 복구 뒤 재시도가 된다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#체크포인트는 한 저장 단위로 커밋되고 실패하면 아무것도 남지 않는다 |
| W22-service-rejects-foreign-revision | scenario | 없는 revision이나 다른 Board의 revision은 rejected_revision_not_found이고 어디에도 체크포인트가 없다 |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#없는 revision이나 다른 Board의 revision에는 붙이지 않는다 |
| W22-service-rejects-archived | scenario | 보관된 Board는 rejected_archived이고 보관 해제 뒤에는 저장된다(0009) |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/task-W22.feature#보관된 Board에는 체크포인트를 저장하지 않는다 |
| W22-checkpoint_request_outcome-R1 | decision-rule | 정리한 제목이 비면 다른 입력과 무관하게 rejected_blank_title |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/W22.decision.yaml#R1 |
| W22-checkpoint_request_outcome-R2 | decision-rule | Board가 없으면 rejected_project_not_found |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/W22.decision.yaml#R2 |
| W22-checkpoint_request_outcome-R3 | decision-rule | 보관된 Board면 rejected_archived(0009) |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/W22.decision.yaml#R3 |
| W22-checkpoint_request_outcome-R4 | decision-rule | revision이 없거나 다른 Board면 rejected_revision_not_found |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/W22.decision.yaml#R4 |
| W22-checkpoint_request_outcome-R5 | decision-rule | 그 Board의 revision이면 현재 여부와 무관하게 saved(체크포인트 하나, revision 불변) |  | .spec-gate/runs/t-w22-72ee8b76/specs/revision-1/W22.decision.yaml#R5 |

## 4. 결정 벡터

### checkpoint_request_outcome

| rule_id | obligation_id | inputs | expected |
| --- | --- | --- | --- |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=active, revision=found, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=active, revision=found, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=active, revision=not_found, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=active, revision=not_found, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=active, revision=other_board, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=active, revision=other_board, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=archived, revision=found, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=archived, revision=found, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=archived, revision=not_found, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=archived, revision=not_found, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=archived, revision=other_board, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=found, board_state=archived, revision=other_board, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=active, revision=found, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=active, revision=found, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=active, revision=not_found, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=active, revision=not_found, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=active, revision=other_board, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=active, revision=other_board, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=archived, revision=found, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=archived, revision=found, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=archived, revision=not_found, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=archived, revision=not_found, revision_currency=not_current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=archived, revision=other_board, revision_currency=current | outcome=rejected_blank_title |
| R1 | W22-checkpoint_request_outcome-R1 | title=blank, project=not_found, board_state=archived, revision=other_board, revision_currency=not_current | outcome=rejected_blank_title |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=active, revision=found, revision_currency=current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=active, revision=found, revision_currency=not_current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=active, revision=not_found, revision_currency=current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=active, revision=not_found, revision_currency=not_current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=active, revision=other_board, revision_currency=current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=active, revision=other_board, revision_currency=not_current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=archived, revision=found, revision_currency=current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=archived, revision=found, revision_currency=not_current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=archived, revision=not_found, revision_currency=current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=archived, revision=not_found, revision_currency=not_current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=archived, revision=other_board, revision_currency=current | outcome=rejected_project_not_found |
| R2 | W22-checkpoint_request_outcome-R2 | title=valid, project=not_found, board_state=archived, revision=other_board, revision_currency=not_current | outcome=rejected_project_not_found |
| R3 | W22-checkpoint_request_outcome-R3 | title=valid, project=found, board_state=archived, revision=found, revision_currency=current | outcome=rejected_archived |
| R3 | W22-checkpoint_request_outcome-R3 | title=valid, project=found, board_state=archived, revision=found, revision_currency=not_current | outcome=rejected_archived |
| R3 | W22-checkpoint_request_outcome-R3 | title=valid, project=found, board_state=archived, revision=not_found, revision_currency=current | outcome=rejected_archived |
| R3 | W22-checkpoint_request_outcome-R3 | title=valid, project=found, board_state=archived, revision=not_found, revision_currency=not_current | outcome=rejected_archived |
| R3 | W22-checkpoint_request_outcome-R3 | title=valid, project=found, board_state=archived, revision=other_board, revision_currency=current | outcome=rejected_archived |
| R3 | W22-checkpoint_request_outcome-R3 | title=valid, project=found, board_state=archived, revision=other_board, revision_currency=not_current | outcome=rejected_archived |
| R4 | W22-checkpoint_request_outcome-R4 | title=valid, project=found, board_state=active, revision=not_found, revision_currency=current | outcome=rejected_revision_not_found |
| R4 | W22-checkpoint_request_outcome-R4 | title=valid, project=found, board_state=active, revision=not_found, revision_currency=not_current | outcome=rejected_revision_not_found |
| R4 | W22-checkpoint_request_outcome-R4 | title=valid, project=found, board_state=active, revision=other_board, revision_currency=current | outcome=rejected_revision_not_found |
| R4 | W22-checkpoint_request_outcome-R4 | title=valid, project=found, board_state=active, revision=other_board, revision_currency=not_current | outcome=rejected_revision_not_found |
| R5 | W22-checkpoint_request_outcome-R5 | title=valid, project=found, board_state=active, revision=found, revision_currency=current | outcome=saved |
| R5 | W22-checkpoint_request_outcome-R5 | title=valid, project=found, board_state=active, revision=found, revision_currency=not_current | outcome=saved |

## 5. 결정

없음

결정 기록:
없음

## 6. Non-blocking notes

- F-W22-12 (W22): 가정은 체크포인트 목록 읽기 실패의 동작을 정했지만 시나리오·obligation이 없다. 가정은 인계 브리프에 실리지 않으므로 TDD는 이 실패 경로를 보지 못하고, Board 단위 체크포인트 조회(새 저장소 메서드)의 실패를 삼켜 체크포인트가 없는 것처럼 revision 행만 그리는 구현이 가능하다. 그 경우 저장된 체크포인트가 조용히 보이지 않게 된다. W17 선례와 같은 '불러오지 못함' 상태로 닫히는 명세 정밀도 문제이고 A10 경계는 바뀌지 않아 minor로 둔다.
- F-W22-13 (W22): 병합 규칙은 revision 기록 시각과 체크포인트 저장 시각의 대소로 자리를 정하는데, 세 UI 시나리오는 연결 revision의 기록 시각을 저장 시각보다 이르게 두는 전제를 적지 않았다. 예를 들어 :176에서 순번 5가 어제 오후 8시에 기록됐다면 규칙상 "어제 메모"는 순번 5 아래·순번 4 위에 오므로 기대 순서(:183)가 틀린다. 테스트 데이터를 그 전제대로 고르면 통과하므로 수용 경계는 바뀌지 않지만, UI 테스트 작성자가 시각을 임의로 고르면 규칙과 무관한 이유로 실패한다.
- F-W22-14 (W22): 단언 범위가 "시트가 열린 전체 기간"이라 사용자가 켜진 채인 '상태 새로고침'을 누르면 참이 아니게 된다. 테스트는 저장 흐름만 실행하므로 실제로는 문제가 없고 obligation description은 저장 동작으로 범위를 좁히고 있다. 구현 테스트는 저장 요청 전후의 어댑터 호출 기록으로 판정하면 된다.
- F-W22-15 (W22): 규칙이 하나로 통일됐다(revision 행 순번 역순 유지, 체크포인트는 기록 시각 ≤ 저장 시각인 첫 revision 행 앞, 없으면 맨 아래, 같은 자리는 시각 역순→순번 역순→ID 순). Examples 15행을 규칙으로 손으로 계산해 모두 일치함을 확인했다: 시계 역행 행(:236 "#2, #1", :237 "c2, c1, #2, #1", :238 "c1, c2, #2, #1"), 동시각 행(:228, :231, :232), 연결 revision이 불러와지지 않은 행(:233, :234), 빈 입력(:224, :235). W17 :216의 순번 유지 순서와도 충돌하지 않는다. 제목·가정·obligation·Feature 서술이 같은 문장이다.
- F-W22-16 (W22): 1차 minor 다섯 건이 모두 요청한 위치에 반영됐고 obligation description과 가정이 함께 갱신됐다. 가정 :52의 요약과 실제 diff가 일치한다.
- F-W22-17 (W22): 결정표는 바뀌지 않았고 완전성·겹침·벡터·obligation 대응을 산출물로 다시 확인했다. 1차 F-W22-7의 판단(revision_currency는 읽지 않는 입력, 저장소 읽기 실패는 표 밖 오류)을 유지한다. A10은 obligation 일곱 개(입력 중 불변·고정 revision 저장·다중·불변·조회·현재 revision 체크포인트 조회·레코드 필드)로 증명되며 각각 위반 시 실패한다.
- F-W22-18 (W22): 인계의 non-blocking note로 넘길 항목: (1) 로그에 제목·메모·다음 할 일 원문 금지는 obligation이 아니라 구현 리뷰 항목, (2) 같은 제목 두 개를 UI 테스트가 구분해야 하면 ID 기반 식별자를 디자인 세션이 DESIGN 11장에서 정한다, (3) DESIGN 16.2 수정·결정 0037은 디자인 세션 몫이고 이 run의 결정 기록 fingerprint와 무관, (4) 앱 종료 시 미저장 입력 폐기는 초안 저장을 하지 않는다는 TECH_STACK 문장으로 닫히며 테스트 대상이 아니다.
- F-W22-19 (W22): 정책 질문으로 올릴 모호성을 찾지 못했다. 병합 순서는 PRD §6-D와 W17 선례로 닫힌 명세 정밀도 문제였고 revision 1에서 하나의 규칙으로 고정됐다. 현재 revision의 체크포인트를 과거 모드로 보는 것, 편집 차단 범위, 보관 거부, 비교 중 행 선택은 각각 디자인 확정 규칙·PRD §6-G·0009·0027이 정한다. 기준 문서·결정 기록과 모순되는 시나리오는 없다.

## 7. 검증 계약

모든 테스트의 이름 또는 태그에 그 테스트가 증명하는 obligation_id를 포함한다. /spec-cycle:verify 가 이 문자열을 찾는다.
