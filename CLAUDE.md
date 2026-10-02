# Fianchetto 프로젝트 규칙

> 계정 공통 규칙(`~/.claude-profiles/personal/CLAUDE.md`)을 전제로 하며, 충돌 시 이 문서가 우선한다.
> GitHub 작업은 개인 계정 `u-nae`로만 한다(`u.naee/.envrc`, direnv).

## 기준 문서와 권한

- 제품 동작: `docs/PRD.md` / 기술 선택: `docs/TECH_STACK.md` / 결정 기록: `docs/decisions/`
- 위임 대상은 최초 기준 문서 두 개(`PRD.md`, `TECH_STACK.md`)뿐이다. 이 두 문서는 1차 초안이며,
  둘 사이의 공백·모순은 에이전트가 판단해 해소하고, 결정마다
  `docs/decisions/NNNN-<slug>.md`(맥락 · 결정 · 대안 · 영향, 짧게)를 남긴다. 결정이 기준 문서를
  바꾸면 해당 문서도 같은 변경에서 갱신한다.
- 명세 작성·구현 중 새로 드러난 정책 모호성은 에이전트 판단을 권장안으로 붙여 사용자에게 질문한다
  (명세 게이트의 `NEEDS_HUMAN`). 사용자 답변은 게이트 종료 후 `docs/decisions/`로 옮긴다.
- 사용자 합의가 필요한 것: 위 정책 모호성, 납품 범위(F01~F12) 축소·확대, 아래 불변식의 의미 변경,
  첫 버전 제외 항목(PRD §4) 도입.
- 명세 게이트: 구현할 작업 단위는 `/fianchetto-spec-gate:run`으로 명세·독립 비평을 통과시킨 뒤
  `READY` 인계(`tdd-handoff.yaml`)의 test obligation을 기준으로 TDD를 진행한다.

## 빌드·테스트

- 표준 `.xcodeproj` + `xcodebuild`. 외부 패키지 0개로 시작한다.
- Swift 6 language mode, strict concurrency complete. 경고를 방치하지 않는다.
- deployment target macOS 15.0, arm64. 개발 기기(macOS 27)에서의 통과를 macOS 15 통과로 보고하지 않는다.
- 프로젝트 `Fianchetto.xcodeproj`, 공유 scheme `Fianchetto`(target: `Fianchetto`, `FianchettoTests`, `FianchettoUITests`).
  소스 폴더는 폴더 동기화 그룹이라 파일 추가 시 pbxproj를 고치지 않는다.

```sh
scripts/verify.sh                    # 전체 검증: 구조·빌드 설정·Debug test(UI 포함)·Release build·entitlement·경고 0개
SKIP_UI_TESTS=1 scripts/verify.sh    # UI 테스트 제외
xcodebuild -project Fianchetto.xcodeproj -scheme Fianchetto -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Fianchetto-verify \
  test -skip-testing:FianchettoUITests   # 단위 테스트만
```

- 빌드 산출물(DerivedData)은 `~/Documents` 밖에 둔다. 저장소가 `~/Documents` 아래라서, 안에 두면 UI 테스트 러너가
  문서 폴더 접근 승인 창을 띄워 키 입력을 가로채고 테스트가 멈춘다.

- 보고할 때 빌드 성공·테스트 통과·macOS 15 실기 실행을 구분한다. `verify.sh` 통과는 macOS 15 실기 검증이 아니다.

## 구조와 의존 방향

한 앱 target, 기능별 폴더. 의존은 위에서 아래로만 흐른다.

```text
Features/<기능>/   SwiftUI View + @Observable @MainActor 화면 상태
Services/          구성 변경·참조·체크포인트·내보내기 오케스트레이션
Domain/            순수 Swift 값 타입과 규칙 (스냅샷, 트리 검증, 차이 비교, 복원·복제 매핑)
Persistence/       SwiftData @Model, VersionedSchema, MigrationPlan, 저장소 어댑터
Platform/          AppKit·파일 시스템 어댑터 (NSOpenPanel, NSWorkspace, 북마크, ImageIO)
App/               진입점, 의존성 조립, Commands, Settings
```

- `Domain`은 `Foundation`만 import한다. SwiftData·SwiftUI·AppKit 금지. 디스크·시간·UUID 생성은 주입한다.
- `@Model` 타입은 `Persistence` 밖으로 나가지 않는다. 경계에서 Domain 값 타입으로 변환한다.
- View는 Service를 직접 조립하지 않고, 저장·파일 접근을 직접 하지 않는다.
- SwiftData 모델과 `ModelContext`를 Task·actor 경계 너머로 넘기지 않는다.
- 파일 I/O·이미지 처리·대량 디코딩은 MainActor 밖에서 한다.
- 복잡한 DI 프레임워크·별도 패키지 분리는 필요가 측정으로 드러날 때 도입한다.

## 데이터 불변식 (PRD §5, 위반 시 버그)

- Node UUID는 이름·부모·순서·대상이 바뀌어도 유지한다. 이름·경로가 같다고 Node를 병합하지 않는다.
- 대상 교체는 새 ResourceReference를 만든다. 과거 revision의 참조·당시 경로는 바뀌지 않는다.
- Revision은 불변이다. 복원·Undo도 새 revision으로 기록한다. 순서는 프로젝트별 순번이 기준이다.
- 현재 구성과 그 revision은 한 저장 단위로 커밋되거나 함께 실패한다. 성공 전에 저장 완료를 표시하지 않는다.
- 취소·무변경·조회·열기·접근 상태 갱신·북마크 갱신은 revision을 만들지 않는다.
- 트리에 순환이 없다. 연결 폴더는 하위 항목의 부모가 될 수 없다.
- 앱은 연결 대상 원본을 이동·복사·수정·삭제하지 않는다. 예외는 사용자가 고른 첨부 이미지의 앱 내부 복사뿐이다.
- 데이터 저장소를 열 수 없을 때 빈 저장소로 조용히 교체하지 않는다.
- 이력은 자동으로 압축·정리·삭제하지 않는다.

## 테스트

- Domain(스냅샷, 차이 비교, 트리 규칙, 복원·복제 ID 재매핑, 가져오기 검증): Swift Testing 단위 테스트. 우선순위 최상.
- Persistence·Service: 실제 SwiftData를 in-memory 또는 임시 디렉토리 `ModelContainer`로 사용한다.
  저장소를 mock으로 대체하지 않는다. 저장 실패는 주입 가능한 실패 지점으로 재현한다.
- 파일 접근: 테스트마다 임시 디렉토리를 만들고 정리한다. 사용자 실제 파일을 건드리지 않는다.
- UI 테스트(XCUITest)는 핵심 흐름만. 성능 검증(A17)은 Release 빌드 + Instruments로 별도 수행한다.
- 테스트 이름은 동작을 서술한다: `@Test("대상 교체 후 이전 revision은 기존 참조를 유지한다")`.
- 수용 기준(A01~A18)과 테스트를 추적 가능하게 연결한다(테스트 태그 또는 이름에 ID 표기).

## UI·문구

- 기본 UI는 한국어, 문자열은 String Catalog로 분리한다.
- 화면 용어(0006): 프로젝트는 **Board**, 로컬 파일·폴더 연결 항목은 **Bishop**(영문 고유 용어 그대로).
  그 밖에 그룹·웹 링크·Board 만들기·새 Bishop·Bishop 추가·Bishop 제거·연결 대상 변경·과거 구성·구성 복원·체크포인트.
  체스 규칙을 기능·문구에 끌어오지 않는다.
- 코드·데이터 모델·내보내기 형식은 중립 용어(Project, Group, Node, ResourceReference)를 쓴다. Board·Bishop은 String Catalog에만 둔다.
- '파일 삭제' 표현과 DB·JSON·bookmark 같은 구현 용어를 화면에 쓰지 않는다.
- 과거/현재, 오류 상태를 색상만으로 구분하지 않는다. 모든 기능은 메뉴·키보드로 접근 가능해야 한다.

## 디자인

- 시각 디자인 규칙은 `docs/DESIGN.md`(초안)를 따른다. 시스템 컨트롤 위에 테마를 얹고, 체스는 시각 톤으로만 쓴다.
- 색은 Asset Catalog Color Set과 생성 심볼로만 참조한다. 코드에 색 값을 직접 쓰지 않는다.
- 디자인 결정(팔레트·아이콘·커스텀 심볼)은 `docs/decisions/`에 기록하고 `DESIGN.md`를 같은 변경에서 갱신한다.
- 화면 캡처는 앱 창만 한다. 전체 화면 캡처는 다른 앱의 개인 정보가 찍힐 수 있다.

## 로그

- `OSLog.Logger`, 서브시스템·카테고리 구분. 메모 원문, 이미지 내용, 전체 구성 JSON, 전체 경로 목록을 로그에 남기지 않는다.
  경로가 필요하면 `privacy: .private`로 기록한다.

## 범위 가드

전체 디스크 인덱싱, 연결 폴더 재귀 스캔·상시 감시, 화면 기록·Accessibility 권한, Git 실행,
서버·계정·분석·동기화, 파일 내용 버전 관리는 첫 버전에 넣지 않는다.
