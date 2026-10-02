# Fianchetto

흩어진 로컬 파일·폴더·웹 링크를 실제 위치는 그대로 둔 채 하나의 **Board**에 모으는 macOS 앱입니다.
Board의 구성이 어떻게 바뀌어 왔는지, 그리고 그때 어디까지 작업했는지를 기억합니다.

> **제품의 약속:** 프로젝트에 어떤 자료가 연결되어 있었고, 그때 어디까지 작업했는지 기억한다.

## 왜 만드나

개발하다 보면 소스 저장소, 문서, 디자인 에셋, 참고 자료가 여러 디렉토리에 흩어집니다. 폴더 구조만으로는
"서비스 A 리팩토링"처럼 여러 위치에 걸친 논리적 작업 단위를 표현하기 어렵고, 시간이 지나면 한 달 전에 무엇을
보며 어디까지 했는지 다시 맞추기도 어렵습니다.

Fianchetto는 파일을 옮기거나 복사하지 않고 **연결만** 모읍니다. 그리고 구성이 바뀔 때마다 자동으로 기록해서
과거 시점의 구성과 작업 메모로 돌아갈 수 있게 합니다.

## 이름과 용어

체스의 피앙케토(Fianchetto)는 비숍을 긴 대각선에 배치하는 수입니다. 비숍이 대각선을 따라 먼 칸까지 닿듯이,
디스크의 먼 위치에 있는 자료까지 한 Board로 이어 준다는 뜻으로 지었습니다. 체스 규칙을 알 필요는 없습니다.

| 화면 용어 | 의미 |
| --- | --- |
| **Board** | 하나의 논리적 프로젝트. 그룹·Bishop·웹 링크를 계층으로 담습니다 |
| **Bishop** | 로컬 파일이나 폴더에 대한 연결. 원본은 원래 자리에 그대로 있습니다 |
| 그룹 | 항목을 묶는 가상 폴더. 디스크에는 존재하지 않습니다 |
| 웹 링크 | 기본 브라우저로 여는 http/https 주소 |
| 체크포인트 | 이름·진행 메모·다음 할 일을 남긴 의미 있는 시점(구현 예정) |

코드와 데이터 형식에는 중립 용어(Project, Group, Node, ResourceReference)를 씁니다([0006](docs/decisions/0006-board-and-bishop-terms.md)).

## 현재 상태

**구현 진행 중: 작업 항목 27개 중 14개 완료(W01–W14).** 구성 편집과 열기까지 실제로 쓸 수 있습니다.
이력 조회·비교·복원, 체크포인트, 내보내기·가져오기는 아직 없습니다.

### 지금 할 수 있는 것

| 기능 | 메뉴 | 단축키 |
| --- | --- | --- |
| Board 만들기 | 파일 > Board 만들기… | ⌘N |
| Bishop 추가(파일·폴더 선택, 또는 Finder에서 끌어다 놓기) | 파일 > Bishop 추가… | ⇧⌘A |
| 연결 대상 변경(이름·위치·이력은 유지하고 대상만 교체) | 파일 > 연결 대상 변경… | ⇧⌘R |
| 그룹 추가 | 파일 > 그룹 추가… | ⌥⌘N |
| 웹 링크 추가 | 파일 > 웹 링크 추가… | ⌥⌘L |
| 열기(기본 앱·기본 브라우저, 트리 행 이중 클릭) | 파일 > 열기 | ⌘O |
| Finder에서 보기 | 파일 > Finder에서 보기 | ⌘R |
| Board 이름 변경 · 보관 · 보관 해제 | 파일 메뉴 | — |
| 항목 이름 변경 · URL 변경 | 편집 메뉴 | — |
| 위로 이동 · 아래로 이동(형제 순서) | 편집 메뉴 | ⌥⌘↑ · ⌥⌘↓ |
| 이동…(다른 그룹·최상위로, 또는 트리 안에서 끌어다 놓기) | 편집 > 이동… | — |
| 제거(현재 구성에서만 빼기, 원본은 그대로) | 편집 > 제거… | ⌘⌫ |

함께 동작하는 것:

- **자동 기록:** 확정한 편집 하나가 구성 기록(revision) 하나로 남습니다. 취소, 바뀐 것이 없는 확정, 열기·조회는 기록하지 않습니다.
- **옮겨진 파일 추적:** Bishop은 파일을 옮겨도 지금 위치로 엽니다. 찾지 못하면 "대상 없음·권한 필요·볼륨 연결 필요·확인 실패" 중 하나로 알려 줍니다.
- **보관된 Board:** 읽기 전용입니다. 편집은 막고 열기·Finder에서 보기는 됩니다.
- **안전한 저장:** 저장에 실패하면 안내하고 화면과 저장소를 이전 상태로 둡니다. 저장소를 열 수 없으면 빈 저장소로 바꾸지 않고 다시 시도·Finder에서 보기·종료를 제안합니다.

### 첫 버전 전체 범위

| ID | 기능 | 상태 |
| --- | --- | --- |
| F01 | Board 생성·이름 변경·보관·보관 해제 | 구현됨 |
| F02 | 중첩 그룹과 파일·폴더·웹 링크 항목 | 구현됨 |
| F03 | 표시 이름, 그룹 위치, 형제 순서 편집 | 구현됨 |
| F04 | 연결 대상 교체, 현재 대상 열기·Finder 표시 | 구현됨 |
| F05 | 구성 변경 자동 기록, 재실행 후 유지 | 구현됨 |
| F11 | 연결 실패 표시와 재연결 | 열기 실패 안내까지 구현. 트리 상태 표시·재연결은 W15 |
| F06 | 이력 목록과 날짜·시점별 읽기 전용 구성 조회 | 예정(W17·W18) |
| F07 | 두 구성의 차이 비교 | 예정(W16·W19) |
| F08 | 과거 구성 복원, 그 구성에서 새 Board 만들기 | 예정(W20·W21) |
| F09 | 체크포인트(이름, 진행 메모, 다음 할 일) | 예정(W22) |
| F10 | 체크포인트 이미지 첨부 | 예정(W23) |
| F12 | Board 내보내기·가져오기 | 예정(W24·W25) |

마지막으로 Release 성능 측정(W26)과 실사용·macOS 15 호환성 검증(W27)을 합니다. 작업 항목 전체는
[docs/work-items.yaml](docs/work-items.yaml)에 있습니다.

## 지키는 것

[PRD §5](docs/PRD.md)의 데이터 불변식 중 사용자에게 중요한 것입니다.

- 앱은 연결한 원본 파일·폴더를 **옮기거나 복사·수정·삭제하지 않습니다.** 제거는 Board에서 빼는 것뿐입니다.
- 항목은 이름·위치·대상이 바뀌어도 같은 항목으로 남고, 과거 기록은 바뀌지 않습니다.
- 이력은 자동으로 정리·삭제하지 않습니다.
- 서버·계정·분석·동기화가 없습니다. 모든 데이터는 이 Mac 안에만 있습니다. 웹 링크를 여는 것은 기본 브라우저의 동작입니다.
- 파일 접근은 App Sandbox 안에서 사용자가 고른 대상에만, 읽기 전용 보안 범위 북마크로 합니다([0001](docs/decisions/0001-sandbox-file-access.md)).

## 요구 사항

- macOS 15.0 이상, Apple Silicon(arm64)
- 빌드: Xcode(Swift 6 지원 버전)

현재는 개발 기기(macOS 27)에서만 확인했습니다. macOS 15 실기 확인은 W27에서 합니다.

## 빌드와 실행

```sh
open Fianchetto.xcodeproj        # Xcode에서 scheme "Fianchetto" 선택 후 ⌘R
```

명령줄:

```sh
scripts/verify.sh                    # 전체 검증: 구조·용어·빌드 설정·Debug 테스트(UI 포함)·Release 빌드·entitlement·경고 0개
SKIP_UI_TESTS=1 scripts/verify.sh    # UI 테스트 제외
xcodebuild -project Fianchetto.xcodeproj -scheme Fianchetto -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Fianchetto-verify \
  test -skip-testing:FianchettoUITests   # 단위 테스트만
```

- 빌드 산출물은 `~/Documents` 밖(`~/Library/Developer/Xcode/DerivedData/Fianchetto-verify`)에 둡니다. 저장소가
  `~/Documents` 아래에 있으면 UI 테스트 러너가 문서 폴더 접근 승인 창을 띄워 테스트가 멈추기 때문입니다.
- **데이터 위치:** 앱은 sandbox 컨테이너의 `~/Library/Containers/io.github.u-nae.Fianchetto/Data/Library/Application Support/Fianchetto/`에
  저장합니다. Xcode에서 Debug로 실행해도 같은 저장소를 쓰므로, 시험할 때는 연습용 Board를 만드는 것을 권합니다.
  단위 테스트는 임시 디렉토리만 쓰고, UI 테스트는 별도 테스트 폴더를 씁니다.
- 아직 서명·배포 설정은 없습니다. 로컬 실행만 대상입니다.

## 구조

한 앱 target에 기능별 폴더를 두고, 의존은 위에서 아래로만 흐릅니다.

```text
Fianchetto/
  App/           진입점, 의존성 조립, 메뉴(Commands)
  Features/      SwiftUI 화면과 @Observable @MainActor 화면 상태 (BoardBrowser)
  Services/      구성 변경 커밋, Bishop 연결, 대상 교체, 보관, 열기
  Domain/        순수 Swift 값 타입과 규칙 (구성 스냅샷, 트리 검증, 편집 연산) — Foundation만 사용
  Persistence/   SwiftData 스키마 V1, 마이그레이션 계획, 저장소 열기·복구, 저장소 어댑터
  Platform/      AppKit·파일 시스템 어댑터 (파일 선택 창, NSWorkspace, 보안 범위 북마크, 로그)
FianchettoTests/     Swift Testing 단위·서비스·화면 상태 테스트 (실제 SwiftData, 임시 디렉토리)
FianchettoUITests/   XCUITest 핵심 흐름
scripts/             검증 스크립트
docs/                기준 문서, 결정 기록, 작업 항목, 디자인 규칙
```

기술 선택: Swift 6(strict concurrency complete), SwiftUI, SwiftData, App Sandbox, 외부 패키지 0개.
현재 구성은 최신 구성 기록(revision)을 가리키는 방식으로 저장합니다([0007](docs/decisions/0007-current-configuration-is-revision-pointer.md)).

## 개발 절차

1. **명세 게이트:** 작업 항목(W01–W27)마다 `fianchetto-spec-gate`로 Gherkin 명세를 쓰고 독립 비평을 통과시킵니다.
   산출물은 `.spec-gate/runs/`에 남습니다.
2. **TDD:** 게이트가 넘긴 test obligation을 테스트 이름에 표기하고(`[W14-open-moved-target] …`), 수용 기준(A01–A18)은 태그로 연결합니다.
   구현 뒤 변이 검사로 테스트가 동작을 실제로 잡는지 확인합니다.
3. **검증:** `scripts/verify.sh` 전체 통과(경고 0개 포함). 빌드 성공·테스트 통과·실제 환경 확인을 구분해 보고합니다.
4. **브랜치·PR:** 작업 항목마다 `feature/wNN-<slug>` 브랜치와 PR을 만들고 merge commit으로 병합합니다.
   아직 병합되지 않은 항목에 의존하면 그 브랜치 위에 PR을 쌓습니다.

## 문서

| 문서 | 내용 |
| --- | --- |
| [docs/PRD.md](docs/PRD.md) | 제품 동작, 데이터 불변식, 수용 기준(A01–A18) |
| [docs/TECH_STACK.md](docs/TECH_STACK.md) | 기술 선택 |
| [docs/decisions/](docs/decisions/) | 기준 문서의 공백·모순 해소와 이후 결정 기록(0001–0013) |
| [docs/work-items.yaml](docs/work-items.yaml) | 구현 작업 항목과 진행 상태 |
| [docs/DESIGN.md](docs/DESIGN.md) | 시각 디자인 규칙(초안) |
| [CLAUDE.md](CLAUDE.md) | 개발 규칙 |
