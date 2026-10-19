# W22 체크포인트 저장과 재개 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 현재 구성에서 파일 메뉴 '체크포인트 저장…'·툴바 깃발 버튼으로 시트를 열어 여는 순간의 현재 revision에 제목·진행 메모·다음 할 일을 담은 불변 체크포인트를 붙이고, 이력 탭의 체크포인트 행으로 그 revision의 과거 구성과 패널을 읽기 전용으로 본다(A10).

**Architecture:** 이력 행 병합은 Domain 순수 함수(`HistoryTimeline.merge`)가 한다. Board·보관·revision 소속 확인과 체크포인트 삽입은 `ProjectStore` actor 안에서 한 저장 단위로 한다(결정표 `checkpoint_request_outcome`, W20·W21과 같은 모양). 저장은 revision을 만들지 않고 `currentRevisionID`를 옮기지 않는다. `HistoryPanelModel`이 체크포인트 목록·선택(`Selection.checkpoint`)·패널 접힘을 맡고, `BoardBrowserModel`은 시트 상태(`CheckpointDraft`)·켜짐 값·패널 표시만 맡는다.

**Tech Stack:** Swift 6(strict concurrency), SwiftUI, SwiftData, Swift Testing(단위), XCUITest(핵심 흐름 1개), `xcodebuild`.

**Spec:** `.spec-gate/runs/t-w22-72ee8b76/spec-brief.md` (READY handoff `tdd-handoff.yaml`의 렌더. 명세 게이트가 brainstorming을 대신했다). 선례 결정 `0009`(보관 Board 거부), `0002`(웹 링크는 revision 구성으로 참조), `0018`·`0035`(메뉴 막대), `0027`(비교 중 행 선택). 디자인 문서는 디자인 세션 PR #64(`docs/DESIGN.md` 16장 체크포인트 절·16.2 flag+개수 제거·식별자, 결정 0037)가 담당하므로 이 계획은 DESIGN.md를 고치지 않는다. 프로젝트 규칙은 `CLAUDE.md`.

## Global Constraints

- 작업 브랜치 `feature/w22-checkpoint`(저장소 `/Users/unae/Documents/u.naee/fianchetto`, 기반 `main` ec0ccb9, 이미 만들어져 있다). 기본 브랜치에 직접 커밋하지 않는다.
- **모든 테스트의 이름 또는 태그에 그 테스트가 증명하는 obligation_id를 포함한다.** 형식은 `@Test("[W22-…] 동작 서술")`. XCUITest는 함수 바로 위 주석에 `// [W22-…]`를 적는다. `/spec-cycle:verify`가 `FianchettoTests/**`와 `FianchettoUITests/**`에서 이 문자열을 찾는다.
- A10을 증명하는 테스트에는 `.tags(.A10)`을 붙인다(`AcceptanceTags.swift`에 `A10` 추가).
- 의존 방향: `Features → Services → Domain`, `Persistence`는 Domain 값 타입만 밖으로 낸다. Domain은 `Foundation`만 import한다. `Persistence`는 `Services`의 타입(`CommitRejection`)을 쓰지 않는다(제네릭 `Skip`으로 넘긴다, `AppendDecision` 선례). 앱 target에 외부 패키지를 더하지 않는다.
- 저장 의미: 체크포인트 하나를 한 저장 단위로 커밋한다. revision을 만들지 않고 `Project.currentRevisionID`를 옮기지 않는다. 레코드: `id = makeID()`, `revisionID = 고정한 revision`, `title = ProjectName.normalize(입력)`(앞뒤 공백·줄바꿈 정리, 비면 거부), `progressNote`·`nextSteps` = 입력 그대로(줄바꿈 포함, 비어도 됨), `createdAt = now()`, `attachments = []`(W23). 같은 제목·같은 revision의 다중 체크포인트를 허용한다. 저장한 체크포인트는 고치거나 지우지 않는다.
- 거부 순서(결정표 FIRST): 빈 제목 → Board 없음 → 보관된 Board(0009) → revision 없음·다른 Board → saved. 서비스는 고정한 revision이 현재 revision인지 확인하지 않는다(PRD §6-G '작성 시작 시 고정'). 저장소 읽기 실패는 outcome이 아니라 오류(throw)다.
- 저장은 파일 시스템·북마크를 해석하지 않는다. 로그에 제목·메모·다음 할 일 원문을 남기지 않는다(체크포인트 ID·순번·실패 종류만).
- 이력 병합 규칙(하나뿐): revision 행은 순번 역순 그대로. 체크포인트 행은 위에서부터 기록 시각이 자기 저장 시각 이하인 첫 revision 행 바로 앞(없으면 맨 아래). 같은 자리의 체크포인트끼리는 저장 시각 역순 → 연결 revision 순번 역순 → ID 문자열 순. 날짜 구역은 행 자신의 시각이 기준이고 `HistorySections.group`처럼 연속 구간으로 만든다.
- 화면 문구는 한국어이고 String Catalog(`Fianchetto/Localizable.xcstrings`)에 `extractionState: manual`로 넣는다(Xcode 서식 `" : "`). 화면에 DB·JSON·bookmark·'그룹'·'파일 삭제'를 쓰지 않는다. 코드 식별자는 중립 용어(Project, Revision, Checkpoint)를 쓴다.
- 문구(디자인 확정, 시안 1A·2A·3B): 파일 메뉴 `체크포인트 저장…`(단축키 없음, '상태 새로고침' 뒤 구분선 다음 단독 그룹, '이 구성으로 복원…' 그룹 앞), 툴바 `flag` 버튼 도움말 `체크포인트 저장`('Wing 추가' 오른쪽·이력 버튼 왼쪽). 시트(폭 480): 제목 `체크포인트 저장`, 부제 `현재 구성 · #n · <기록 시각> 기록`, 라벨 `제목`(안내 `예: 인증 리팩토링 1차 완료`)·`진행 메모`·`다음 할 일`, 안내 `저장한 체크포인트는 고칠 수 없습니다. 고치려면 같은 구성에 새로 저장합니다.`, 버튼 `취소`(Esc)·`저장`(기본), 실패 `exclamationmark.triangle` + `저장하지 못했습니다. 입력한 내용은 그대로 있으니 다시 시도하세요.`. 이력 행: `flag.fill` + 제목, 아래 `체크포인트 · #n · <시각>`, VoiceOver `체크포인트, <제목>, #n 구성, <시각> 저장`. 패널: `flag.fill` + 제목 + `<날짜 시각> 저장` + 접기 버튼(도움말 `체크포인트 접기`/`체크포인트 펴기`), 열 라벨 `진행 메모`·`다음 할 일`(공백뿐이면 열 없음).
- 접근성 식별자: `checkpoint-sheet-title`, `checkpoint-title-field`, `checkpoint-memo-field`, `checkpoint-next-field`, `checkpoint-cancel`, `checkpoint-save`, `checkpoint-save-error`, `checkpoint-row-<제목>`, `checkpoint-panel`, `checkpoint-panel-toggle`, `checkpoint-toolbar`. 기존 `restore-menu`·`past-banner`·`revision-row-<순번>`은 그대로.
- 시트가 열린 동안: 구성 편집(편집 메뉴 전부, Bishop·Wing·웹 링크 추가, 연결 대상 변경), Board 이름 변경, Board 보관·보관 해제, 이 구성으로 복원·새 Board 만들기, Board 만들기(⌘N), '다시 선택…'은 동작하지 않는다. 열기·Finder에서 보기·상태 새로고침·이력 보기·인스펙터·사이드바는 그대로다.
- 테스트: Persistence·Service는 임시 디렉터리의 실제 SwiftData 저장소(`ServiceHarness`, `BrowserHarness`)를 쓰고 mock으로 대체하지 않는다. 저장 실패는 `FaultPoint.failNext()`로 주입한다. sleep·무작위 데이터 금지. 임시 디렉터리는 `withTemporaryDirectoryAsync`가 정리한다. 시각이 중요한 이력 테스트는 `HistoryModelTests`처럼 `withStore`로 revision·체크포인트를 원하는 `recordedAt`·`createdAt`으로 직접 심는다.
- 단위 테스트 실행(호스트, 화면을 막지 않음):
  ```sh
  xcodebuild -project Fianchetto.xcodeproj -scheme Fianchetto -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Fianchetto-verify \
    test -skip-testing:FianchettoUITests -only-testing:FianchettoTests/<SuiteTypeName>
  ```
  아래에서 `UNIT <Suite>`는 이 명령을 뜻한다. `UNIT ALL`은 `-only-testing`을 뺀 것이다.
- **XCUITest를 호스트에서 실행하지 않는다**(키보드·마우스를 가져간다). UI 테스트는 `scripts/vm-verify.sh`(Tart 가상 머신 `fianchetto-ui`)로만 실행한다. 호스트 전체 검증·VM 사용 전후에 디자인 세션(`fianchetto-design`)에 `SendMessage`로 알린다. 호스트 `SKIP_UI_TESTS=1 scripts/verify.sh`가 TileIconSnapshotTests 라이트 2장 불일치로만 실패하면 '알려진 호스트 드리프트'로 적고 VM 결과를 기준으로 보고한다(사용자 결정 2026-10-19). 다른 이미지가 어긋나면 고친다.
- 경고 0개(Swift 6 strict concurrency). `scripts/verify.sh`가 검사한다.
- 커밋 메시지: `[Area] Imperative subject`(영어, 대문자 시작, 마침표 없음, ≤72자), 본문은 왜를 72자 줄바꿈으로, 마지막 줄 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- `BoardBrowserModel.swift`는 약 1,960줄이다. 체크포인트 흐름(약 120줄)은 그 파일의 새 `// MARK: 체크포인트(W22)` 절에 둔다. 파일 분리는 이 계획의 범위가 아니다. 디자인 세션 PR #64(`gh pr diff 64 -- docs/DESIGN.md`)가 이 계획보다 세부적인 시각 규칙(간격·글꼴·색 토큰)을 정하면 obligation을 바꾸지 않는 범위에서 그것을 따른다.

## Review Focus

1. **시트를 연 채 다른 Board를 고른다** — 시트가 닫히고 뒤늦은 저장 결과가 화면·목록에 쓰이면 안 된다. (Task 4 테스트)
2. **제목이 줄바꿈·탭뿐이다** — 정리하면 비므로 '저장'이 꺼지고 서비스도 거부한다. (Task 2 결정표 R1, Task 4 테스트)
3. **체크포인트를 보는 중 다른 Board를 고른다** — 선택·패널·체크포인트 목록이 비워지고 새 Board의 현재 구성이 보인다. (Task 3 테스트)
4. **체크포인트를 고른 채 이력 탭을 닫는다(항목 탭)** — W18처럼 과거 구성 띠와 패널은 이어진다. (Task 4 테스트)
5. **이력 탭을 아직 열지 않은 채 저장한다** — 저장 직후의 행 추가는 무시되고 탭을 열 때 한 번 읽어 중복 행이 없다. (Task 3 테스트)

---

## 파일 구조

| 경로 | 책임 | task |
| --- | --- | --- |
| `Fianchetto/Domain/Records.swift` | `CheckpointSummary` 값 타입 | 1 |
| `Fianchetto/Domain/RevisionHistory.swift` | `HistoryTimeline.merge` 순수 병합 | 1 |
| `FianchettoTests/Domain/HistoryTimelineTests.swift` | 병합 규칙 15행 | 1 |
| `FianchettoTests/Domain/AcceptanceTags.swift` | `A10` 태그 | 1 |
| `Fianchetto/Persistence/StoreAdapter.swift` | Board 단위 체크포인트 목록·레코드 읽기 | 2 |
| `Fianchetto/Persistence/ProjectStore.swift` | actor 안 확인 + 한 저장 단위 삽입, 현재 revision 목록 정보 | 2 |
| `Fianchetto/Services/ConfigurationService.swift` | `saveCheckpoint`와 순수 판정 `decideCheckpoint` | 2 |
| `FianchettoTests/Services/CheckpointServiceTests.swift` | 결정표 48칸, 서비스·저장소 시나리오 | 2 |
| `Fianchetto/Features/BoardBrowser/HistoryPanelModel.swift` | 체크포인트 목록·행 병합·선택·패널 접힘 | 3 |
| `FianchettoTests/Features/CheckpointHistoryModelTests.swift` | 이력 탭 행·순서·묶음·선택 | 3 |
| `Fianchetto/Features/BoardBrowser/BoardBrowserModel.swift` | 시트 상태, 켜짐 값, 시작·취소·확정, 패널, 비교 매핑 | 4 |
| `FianchettoTests/Features/BoardBrowserTestSupport.swift` | `BrowserHarness.serviceClock` 노출 | 4 |
| `FianchettoTests/Features/CheckpointModelTests.swift` | 화면 모델 흐름 | 4 |
| `Fianchetto/Features/BoardBrowser/CheckpointSheet.swift` | 저장 시트 View | 5 |
| `Fianchetto/Features/BoardBrowser/CheckpointPanelView.swift` | 조회 패널 View | 5 |
| `Fianchetto/Features/BoardBrowser/HistoryTabView.swift` | 체크포인트 행, 묶음 트리거 | 5 |
| `Fianchetto/Features/BoardBrowser/BoardBrowserView.swift` | 툴바 깃발, 패널 배치, `.sheet` 연결 | 5 |
| `Fianchetto/App/BoardCommands.swift` | 파일 메뉴 '체크포인트 저장…' | 5 |
| `Fianchetto/Localizable.xcstrings`, `scripts/check-terms.sh` | 문구, 용어 검사 | 5 |
| `FianchettoUITests/BoardBrowserUITests.swift` | 핵심 흐름 UI 테스트 1개 | 5 |

---

### Task 1: Domain — 체크포인트 목록 정보와 이력 병합

**Obligations:** W22-timeline-merge-pure

**Files:**
- Modify: `Fianchetto/Domain/Records.swift` (`CheckpointRecord` 아래)
- Modify: `Fianchetto/Domain/RevisionHistory.swift` (`HistorySections` 아래)
- Modify: `FianchettoTests/Domain/AcceptanceTags.swift` (`@Tag static var A10: Self` 추가, A09 다음)
- Create: `FianchettoTests/Domain/HistoryTimelineTests.swift`

**Interfaces:**
- Consumes: `RevisionSummary`, 테스트 지원 `fixedID`, `date(_:)`.
- Produces:
  ```swift
  // Records.swift
  /// 이력 탭 체크포인트 행의 목록 정보(W22). 메모 본문은 싣지 않는다. 연결 revision의 순번을 함께 둔다.
  struct CheckpointSummary: Hashable, Sendable, Identifiable {
      var id: UUID
      var revisionID: UUID
      var sequence: Int
      var title: String
      var createdAt: Date
  }

  // RevisionHistory.swift
  /// 이력 탭의 revision 행과 체크포인트 행 병합(W22). revision 행은 순번 역순 그대로, 체크포인트 행은 기록 시각이
  /// 저장 시각 이하인 첫 revision 행 앞(없으면 맨 아래). 같은 자리는 저장 시각 역순 → 순번 역순 → ID 문자열 순. 입력을 바꾸지 않는다.
  enum HistoryTimeline {
      enum Entry: Equatable, Sendable {
          case revision(RevisionSummary)
          case checkpoint(CheckpointSummary)
      }
      static func merge(revisions: [RevisionSummary], checkpoints: [CheckpointSummary]) -> [Entry]
  }
  ```
  알고리즘(결과를 결정하므로 적는다): `revisions`를 순번 역순으로 정렬하고, `checkpoints`를 `(createdAt 역순, sequence 역순, id.uuidString 오름차순)`으로 정렬해 `pending`에 둔다. revision을 위에서부터 돌며 `pending`의 앞에서 `createdAt >= revision.recordedAt`인 동안 꺼내 `.checkpoint`로 더한 뒤 `.revision`을 더한다. 끝나면 남은 `pending`을 순서대로 더한다.

- [ ] **Step 0: 게이트 산출물과 계획 커밋**

```bash
cd /Users/unae/Documents/u.naee/fianchetto
git add .spec-gate/runs/t-w22-72ee8b76 docs/work-items.yaml docs/superpowers/plans/2026-10-19-w22-checkpoint.md
git commit -m "[Spec] Record W22 gate handoff and plan"
```
본문에 "W22 checkpoint passed the specification gate (run t-w22-72ee8b76) with no human decisions; keep the handoff, brief and the plan with the code they justify."를 쓰고 Co-Authored-By 줄을 붙인다.

- [ ] **Step 1: 실패하는 테스트 작성** — `HistoryTimelineTests.swift`, `@Suite("이력 행 병합 (W22)")`

  fixture: `rev(_ n: Int, _ t: Double) -> RevisionSummary`(id `fixedID(7000 + n)`, projectID `fixedID(500)`, sequence n, recordedAt `date(t)`, cause `.edited(.renameNode)`, projectName "서비스 A"), `cp(_ k: Int, _ n: Int, _ t: Double) -> CheckpointSummary`(id `fixedID(7100 + k)`, revisionID `fixedID(7000 + n)`, sequence n, title "c\(k)", createdAt `date(t)`). 시각은 t1 = 10, t1.5 = 15, t2 = 20, t3 = 30, t4 = 40. `fixedID(7101).uuidString < fixedID(7102).uuidString`을 테스트 안에서 `#require`로 확인한다(ID 순 전제).

  `struct Case: CustomTestStringConvertible { var name: String; var revisions: [RevisionSummary]; var checkpoints: [CheckpointSummary]; var expected: [String] }` — expected는 `"#2"`, `"c1"` 같은 짧은 이름. `name(of entry) -> String`.

  `@Test("[W22-timeline-merge-pure] revision 행은 순번 역순 그대로, 체크포인트 행은 기록 시각이 저장 시각 이하인 첫 revision 행 앞", arguments: cases)` — 명세 outline 15행 그대로:
  | revisions | checkpoints | expected |
  |---|---|---|
  | [] | [] | [] |
  | 1(t1), 2(t2) | [] | #2, #1 |
  | 1(t1), 2(t2) | c1(#2,t3) | c1, #2, #1 |
  | 1(t1), 2(t2), 3(t3) | c1(#1,t4) | c1, #3, #2, #1 |
  | 1(t1), 2(t2) | c1(#2,t2) | c1, #2, #1 |
  | 1(t1), 2(t2) | c1(#1,t1.5) | #2, c1, #1 |
  | 1(t1), 2(t2) | c1(#2,t3), c2(#2,t4) | c2, c1, #2, #1 |
  | 1(t1), 2(t2) | c1(#1,t3), c2(#2,t3) | c2, c1, #2, #1 |
  | 1(t1), 2(t2) | c1(#2,t3), c2(#2,t3) | c1, c2, #2, #1 |
  | 2(t2) | c1(#1,t3) | c1, #2 |
  | 2(t2) | c1(#1,t1) | #2, c1 |
  | [] | c1(#1,t1) | c1 |
  | 1(t2), 2(t1) | [] | #2, #1 |
  | 1(t2), 2(t1) | c1(#1,t1.5), c2(#2,t3) | c2, c1, #2, #1 |
  | 1(t2), 2(t1) | c1(#1,t4), c2(#2,t1) | c1, c2, #2, #1 |
  단언: `merge(...)`의 이름 배열 == expected; 입력 배열을 `let before = (revisions, checkpoints)`로 잡아 호출 뒤 같음; 같은 입력으로 두 번 호출한 결과가 같음; **입력 revisions 순서를 뒤집어 넣어도 결과가 같다**(순번 역순 정렬은 함수 책임).

- [ ] **Step 2: 실패 확인** — Run: `UNIT HistoryTimelineTests`. Expected: 컴파일 실패(`HistoryTimeline`·`CheckpointSummary` 없음).

- [ ] **Step 3: 구현** — Interfaces대로. `A10` 태그를 더한다.

- [ ] **Step 4: 통과 확인** — Run: `UNIT HistoryTimelineTests`. Expected: 15행 전부 통과.

- [ ] **Step 5: Commit**

```bash
git add Fianchetto/Domain/Records.swift Fianchetto/Domain/RevisionHistory.swift \
  FianchettoTests/Domain/HistoryTimelineTests.swift FianchettoTests/Domain/AcceptanceTags.swift
git commit -m "[Domain] Merge checkpoint rows into the revision timeline"
```
본문: PRD §6-D의 순번 기준(revision)과 체크포인트의 저장 시각을 한 규칙으로 섞어 시계 역행에서도 결정적이게 했다는 이유를 쓴다.

---

### Task 2: 저장소 커밋과 서비스 판정

**Obligations:** W22-service-outcome-table, W22-service-record-fields, W22-service-atomic-commit, W22-service-rejects-foreign-revision, W22-service-rejects-archived, W22-checkpoint_request_outcome-R1, W22-checkpoint_request_outcome-R2, W22-checkpoint_request_outcome-R3, W22-checkpoint_request_outcome-R4, W22-checkpoint_request_outcome-R5, W22-title-trimmed-notes-verbatim, W22-optional-notes-empty, W22-multiple-checkpoints-same-revision, W22-checkpoint-immutable-after-edit, W22-history-paging-keeps-rows

**Files:**
- Modify: `Fianchetto/Persistence/StoreAdapter.swift`
- Modify: `Fianchetto/Persistence/ProjectStore.swift`
- Modify: `Fianchetto/Services/ConfigurationService.swift`
- Create: `FianchettoTests/Services/CheckpointServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 `CheckpointSummary`; 기존 `CheckpointRecord`, `StoreAdapter.insert(_ checkpoint:)`(revision 존재 검사 포함), `StoreAdapter.record(_: CheckpointModel)`(private, 재사용), `ProjectStore.commit()`, `ProjectName.normalize`, `RevisionSummary`; 테스트 지원 `ServiceHarness`, `makeBoard`, `FaultPoint`, `TestIDs`, `TestClock`, `withStore(at:)`, `withTemporaryDirectoryAsync`, `TargetFiles`, `SnapshotFixtures`, `RecordFixtures`, `date(_:)`.
- Produces:
  ```swift
  // StoreAdapter.swift — MARK: 읽기
  /// Board의 모든 체크포인트 목록 정보(W22). revision을 먼저 읽어 순번을 붙이고 저장 시각 역순으로 돌려준다. 메모 본문은 싣지 않는다.
  func checkpointSummaries(projectID: UUID) throws(StoreReadError) -> [CheckpointSummary]
  func checkpoint(_ id: UUID) throws(StoreReadError) -> CheckpointRecord?

  // ProjectStore.swift — 파일 위쪽 타입들 옆
  /// 체크포인트를 붙일 revision을 저장소에서 읽은 결과(W22).
  enum CheckpointRevision: Equatable, Sendable { case found(RevisionSummary); case notFound; case otherProject }
  enum CheckpointSource: Sendable { case projectNotFound; case found(ProjectRecord, CheckpointRevision) }
  enum CheckpointDecision<Skip: Sendable>: Sendable { case save(CheckpointRecord); case skip(Skip) }
  enum CheckpointResult<Skip: Sendable>: Sendable { case saved(CheckpointRecord); case skipped(Skip) }

  // ProjectStore — MARK: 커밋
  /// Board와 revision을 같은 actor 안에서 읽어 `decide`에 주고, 저장하기로 하면 체크포인트 하나를 한 저장 단위로 커밋한다.
  /// revision을 만들지 않고 currentRevisionID를 옮기지 않는다(PRD §6-G, A10).
  func saveCheckpoint<Skip: Sendable>(
      on revisionID: UUID, of projectID: UUID,
      decide: @Sendable (CheckpointSource) -> CheckpointDecision<Skip>
  ) throws(ProjectStoreError) -> CheckpointResult<Skip>
  // ProjectStore — MARK: 읽기
  /// 현재 revision의 목록 정보. Board가 없으면 nil. 시트를 열 때 revision을 고정하는 데 쓴다.
  func currentRevisionSummary(projectID: UUID) throws(StoreReadError) -> RevisionSummary?
  func checkpointSummaries(projectID: UUID) throws(StoreReadError) -> [CheckpointSummary]
  func checkpoint(_ id: UUID) throws(StoreReadError) -> CheckpointRecord?

  // ConfigurationService.swift
  enum CommitRejection { …; /// 체크포인트 제목이 비어 있다(W22). case blankTitle }
  enum CheckpointOutcome: Equatable, Sendable { case saved(CheckpointRecord); case rejected(CommitRejection) }
  /// 고정한 revision에 체크포인트를 붙인다(W22, 결정표 checkpoint_request_outcome). 판단과 커밋은 저장소 actor 안에서 한다.
  func saveCheckpoint(title: String, progressNote: String, nextSteps: String, on revisionID: UUID, in projectID: UUID)
      async throws(ConfigurationServiceError) -> CheckpointOutcome
  /// 순서(FIRST): 제목 → Board → 보관(0009) → revision(없음·다른 Board) → 저장. 현재 revision 여부는 읽지 않는다.
  static func decideCheckpoint(
      title: String, progressNote: String, nextSteps: String, source: CheckpointSource, now: () -> Date, makeID: () -> UUID
  ) -> CheckpointDecision<CommitRejection>
  ```
  `saveCheckpoint`(store): `adapter.project(projectID)` 없으면 `.projectNotFound`; `adapter.revisionSummary(revisionID)` 없으면 `.notFound`, `projectID`가 다르면 `.otherProject`, 있으면 `.found(summary)`; 읽기 실패는 `.storeUnavailable`을 던진다. `.save(record)`면 `adapter.insert(record)` → 실패 시 `modelContext.rollback()` 후 `.storeUnavailable`; `try commit()`; `.saved(record)`.
  `decideCheckpoint`: `ProjectName.normalize(title)` 실패 → `.skip(.blankTitle)`; `.projectNotFound` → `.skip(.projectNotFound)`; `project.archivedAt != nil` → `.skip(.archived)`; `.notFound`/`.otherProject` → `.skip(.revisionNotFound)`; `.found(summary)` → `.save(CheckpointRecord(id: makeID(), revisionID: summary.id, title: normalized, progressNote: progressNote, nextSteps: nextSteps, createdAt: now(), attachments: []))`.
  `saveCheckpoint`(service): `store.saveCheckpoint(on:of:) { Self.decideCheckpoint(…) }` → `.saved` → `.saved(record)`, `.skipped(rejection)` → `.rejected(rejection)`, 던져진 `ProjectStoreError`는 `Self.map`.
  `checkpointSummaries`(adapter): 그 Board의 `RevisionModel`을 읽어 `[revisionID: sequence]`를 만들고, `let ids = Array(map.keys)`로 `FetchDescriptor<SchemaV1.CheckpointModel>(predicate: #Predicate { ids.contains($0.revisionID) }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])`를 읽어 `CheckpointSummary`로 바꾼다. revision이 없는 Board는 빈 배열.

- [ ] **Step 1: 결정표 테스트 작성(실패)** — `CheckpointServiceTests.swift`, `@Suite("체크포인트 저장 서비스 (W22)")`

  `DuplicateServiceTests`의 `Cell` 방식: `enum Outcome: String { case rejectedBlankTitle, rejectedProjectNotFound, rejectedArchived, rejectedRevisionNotFound, saved }`, `enum Revision: String { case found, notFound, otherBoard }`, `struct Cell { rule, blankTitle: Bool, projectFound: Bool, archived: Bool, revision: Revision, current: Bool, expected }`. 48칸을 R1(24)·R2(12)·R3(6)·R4(4)·R5(2)로 만든다(spec-brief §4의 셀 지도와 같다). `source(cell)`: `projectFound`가 거짓이면 `.projectNotFound`; 아니면 `ProjectRecord(id: fixedID(10), createdAt: date(0), currentRevisionID: cell.current ? summary.id : fixedID(22), archivedAt: cell.archived ? date(5) : nil, origin: nil)`와 revision(`found` → `.found(summary)`(id `fixedID(21)`, sequence 5, recordedAt `date(20)`), `notFound` → `.notFound`, `otherBoard` → `.otherProject`). `decide(cell)`: `decideCheckpoint(title: cell.blankTitle ? " \n\t " : "  인증 1차 ", progressNote: "로그인 완료\n", nextSteps: "토큰 갱신", source:, now: { date(99) }, makeID: { fixedID(7001) })`. `classify`: `.save(record)`면 `record.revisionID == fixedID(21)`, `title == "인증 1차"`, `progressNote == "로그인 완료\n"`, `nextSteps == "토큰 갱신"`, `createdAt == date(99)`, `attachments.isEmpty`, `id == fixedID(7001)`을 단언하고 `.saved`; `.skip(.blankTitle)` 등은 대응 Outcome.
  - `@Test("[W22-checkpoint_request_outcome-R1] 정리한 제목이 비면 다른 입력과 무관하게 거부한다", arguments: cells.filter { $0.rule == "R1" })`
  - `@Test("[W22-checkpoint_request_outcome-R2] Board가 없으면 거부한다", …R2)`
  - `@Test("[W22-checkpoint_request_outcome-R3] 보관된 Board면 거부한다(0009)", …R3)`
  - `@Test("[W22-checkpoint_request_outcome-R4] revision이 없거나 다른 Board면 거부한다", …R4)`
  - `@Test("[W22-checkpoint_request_outcome-R5] 그 Board의 revision이면 현재 여부와 무관하게 저장한다", …R5)`
  - `@Test("[W22-service-outcome-table] 결정표의 모든 칸은 정확히 한 규칙이 이긴다")` — `cells.count == 48`, (blankTitle, projectFound, archived, revision, current) 조합이 중복 없이 48개.

- [ ] **Step 2: 실패 확인** — Run: `UNIT CheckpointServiceTests`. Expected: 컴파일 실패(`decideCheckpoint` 없음).

- [ ] **Step 3: 구현** — Interfaces의 타입·`decideCheckpoint`·adapter·store 메서드·서비스 메서드.

- [ ] **Step 4: 통과 확인** — Run: `UNIT CheckpointServiceTests`. Expected: 결정표 테스트 전부 통과.

- [ ] **Step 5: 서비스·저장소 시나리오 테스트 작성(실패)**

  fixture `seeded(_ directory: URL) async throws -> Seeded`(`ServiceHarness(directory:)`): ① `makeBoard(_, "서비스 A")` ② `linking.link`로 Bishop 폴더 `backend`(`TargetFiles.folder(directory, "targets/backend")`, 안에 `marker.txt`) ③ `.addGroup(name: "개발")` ④ `.addWebLink(name: "명세", url: "https://example.com/spec", parentID: 개발)` ⑤ `.addGroup(name: "문서")` ⑥ `.changeURL(명세, "https://example.com/spec-v2")`. 순번 1…6, 현재 순번 6. 다른 Board "서비스 Z"(순번 1). `Seeded`는 `harness`, `project`, `other`, `revisionID(_ sequence:)`, `summaries()`, `currentRevisionID()`, `checkpoints(of sequence:)`(= `store.checkpoints`… 없으므로 `withStore(at: harness.url)`가 아니라 `harness.store.checkpointSummaries(projectID:)`를 순번으로 거른 것), `checkpointCount()`(= `checkpointSummaries(projectID: project).count`)를 제공한다. 저장 헬퍼 `save(_ s: Seeded, _ title: String = "인증 1차", note: String = "로그인 완료", next: String = "토큰 갱신", on sequence: Int = 6, at: Double? = nil) async throws -> CheckpointOutcome` — `at`이 있으면 `ConfigurationService(store: s.harness.store, now: { date(at) }, makeID: { ids.make() })`(`ids = TestIDs(startingAt: 9001)`)로 저장하고, 없으면 `s.harness.service`로 저장한다.

  - `@Test("[W22-service-record-fields] 저장된 레코드는 고정 revision·정리한 제목·입력 그대로의 메모·주입 시계 시각·빈 첨부를 가지고 revision은 그대로다", .tags(.A10))` — `save(s, "  인증 1차 ", note: "로그인 완료\n", at: 5000)` → `.saved(record)`; `record.revisionID == revisionID(6)`, `title == "인증 1차"`, `progressNote == "로그인 완료\n"`, `nextSteps == "토큰 갱신"`, `createdAt == date(5000)`, `attachments.isEmpty`; `summaries().count == 6`, `currentRevisionID() == revisionID(6)`; `store.checkpoint(record.id) == record`; 같은 요청을 다시 보내면 다른 id의 레코드가 생기고 `checkpoints(of: 6).count == 2`.
  - `@Test("[W22-title-trimmed-notes-verbatim] 제목은 앞뒤 공백을 정리하고 메모는 줄바꿈까지 그대로 저장한다")` — `save(s, "  인증 1차  ", note: "로그인 완료\n토큰 갱신 남음", next: "  갱신 구현 ")` → 레코드 `title == "인증 1차"`, `progressNote == "로그인 완료\n토큰 갱신 남음"`, `nextSteps == "  갱신 구현 "`.
  - `@Test("[W22-optional-notes-empty] 진행 메모와 다음 할 일이 비어 있어도 저장된다")` — `save(s, "빈 메모", note: "", next: "")` → `.saved`, `progressNote == ""`, `nextSteps == ""`, `checkpointCount() == 1`.
  - `@Test("[W22-multiple-checkpoints-same-revision] 같은 revision에 여러 체크포인트를 붙일 수 있고 목록은 저장 시각 역순이다", .tags(.A10))` — `save(s, "1차", at: 100)`, `save(s, "2차", at: 200)` → `checkpointSummaries(projectID:)`의 제목이 `["2차", "1차"]`, 둘 다 `sequence == 6`, id가 다름, `summaries().count == 6`.
  - `@Test("[W22-checkpoint-immutable-after-edit] 저장 뒤 구성이 바뀌어도 체크포인트는 원래 revision에 그대로다", .tags(.A10))` — `save(s, "1차")` → `.addGroup(name: "임시")`(순번 7) → `checkpointSummaries`가 하나이고 `sequence == 6`, `store.checkpoint(id)`의 모든 필드가 저장 때와 같음, `checkpoints(of: 7).isEmpty`, `currentRevisionID() == revisionID(7)`.
  - `@Test("[W22-service-atomic-commit] 저장이 실패하면 아무것도 남지 않고 복구 뒤 다시 저장할 수 있다")` — `harness.fault.failNext()` → `await #expect(throws: ConfigurationServiceError.saveFailed) { try await save(s, "실패") }` → `checkpointCount() == 0`, `summaries().count == 6`, `currentRevisionID() == revisionID(6)`; 다시 `save` → `.saved`, `checkpointCount() == 1`.
  - `@Test("[W22-service-rejects-foreign-revision] 없는 revision이나 다른 Board의 revision에는 붙이지 않는다", arguments: [true, false])` — `on: 다른 Board 순번 1 ID` / `fixedID(404)` → `.rejected(.revisionNotFound)`, 두 Board의 `checkpointSummaries`가 모두 비어 있음.
  - `@Test("[W22-service-rejects-archived] 보관된 Board에는 저장하지 않고 보관 해제 뒤에는 저장한다")` — `store.setArchived(project, at: date(100))` → `.rejected(.archived)`, `checkpointCount() == 0`; `setArchived(project, at: nil)` → `.saved`, `checkpointCount() == 1`.
  - `@Test("[W22-checkpoint_request_outcome-R2] 없는 Board의 요청은 거부된다")` — `in: fixedID(404)` → `.rejected(.projectNotFound)`.
  - `@Test("[W22-history-paging-keeps-rows] Board의 체크포인트 목록은 모든 revision의 것을 순번과 함께 한 번에 읽고 다른 Board의 것은 뺀다")` — `withStore(at:)`로 `RecordFixtures` Board(P: R1 순번 1, R2 순번 2)와 다른 Board(순번 1)를 심고 체크포인트 C1(R2, `date(60)`), C2(R1, `date(90)`), C3(다른 Board, `date(70)`)을 `insert` → `ProjectStore(container:).checkpointSummaries(projectID: P)`가 `[C2(순번 1, 90), C1(순번 2, 60)]`이고 C3이 없음; `currentRevisionSummary(projectID: P)?.id == R2`; 없는 Board는 `nil`.

- [ ] **Step 6: 실패 확인 후 필요한 만큼 구현, 통과 확인** — Run: `UNIT CheckpointServiceTests`. Expected: 전부 통과.

- [ ] **Step 7: 전체 단위 테스트** — Run: `UNIT ALL`. Expected: 기존 테스트 포함 전부 통과, 새 경고 없음(`CommitRejection` case 추가로 깨지는 exhaustive switch가 있으면 `.rejected` 포괄 분기를 확인한다).

- [ ] **Step 8: Commit**

```bash
git add Fianchetto/Persistence/StoreAdapter.swift Fianchetto/Persistence/ProjectStore.swift \
  Fianchetto/Services/ConfigurationService.swift FianchettoTests/Services/CheckpointServiceTests.swift
git commit -m "[Checkpoint] Save a checkpoint on a fixed revision inside the store actor"
```
본문: Board·보관·revision 소속 확인과 삽입을 한 저장 단위로 묶어 결과가 커밋 시점 기준이 되게 했고, revision을 만들지 않으며 currentRevisionID를 옮기지 않는다(A10)는 이유를 쓴다.

---

### Task 3: 이력 탭 모델 — 체크포인트 행·선택·묶음

**Obligations:** W22-history-row-shape, W22-history-row-order, W22-history-old-revision-new-checkpoint, W22-history-no-count-on-revision-rows, W22-history-paging-keeps-rows, W22-unreadable-revision-notice, W22-switch-to-revision-row, W22-return-to-current, W22-select-current-revision-checkpoint, W22-weblink-from-revision

**Files:**
- Modify: `Fianchetto/Features/BoardBrowser/HistoryPanelModel.swift`
- Modify: `Fianchetto/Features/BoardBrowser/HistoryTabView.swift` (`Section.rows` → `entries` 이름 변경에 따른 최소 수정만. 체크포인트 행 View는 Task 5)
- Create: `FianchettoTests/Features/CheckpointHistoryModelTests.swift`

**Interfaces:**
- Consumes: Task 1 `HistoryTimeline.merge`, `CheckpointSummary`; Task 2 `ProjectStore.checkpointSummaries(projectID:)`, `checkpoint(_:)`, `revisionSummary(_:)`, `snapshot(revisionID:)`; 기존 `Row`, `rows(from:store:)`, `selectionRequested`, `selectionChanged`, `HistorySections.group`, `dateTimeText`, `timeText`.
- Produces:
  ```swift
  enum Selection: Hashable { case current; case revision(UUID); case checkpoint(UUID) }
  /// 목록 한 행: revision 행 또는 체크포인트 행(W22).
  enum Entry: Identifiable, Equatable {
      case revision(Row)
      case checkpoint(CheckpointSummary)
      var id: UUID   // row.id / summary.id
  }
  struct Section: Identifiable, Equatable { var day: Date; var title: String; var entries: [Entry]; var id: Date { day } }
  /// Board의 모든 체크포인트 목록 정보. open()에서 revision 첫 묶음과 함께 한 번 읽는다.
  private(set) var checkpoints: [CheckpointSummary]
  /// 고른 체크포인트(패널 내용). nil이면 revision 행 또는 '현재 구성'을 골랐다.
  private(set) var selectedCheckpoint: CheckpointRecord?
  /// 패널 접힘(화면 상태). 체크포인트를 고를 때마다 false로 돌아간다.
  var isCheckpointCollapsed = false
  /// rows(순번 역순)와 checkpoints의 병합. sections는 이것을 연속 구간으로 묶는다.
  var entries: [Entry]
  var selection: Selection          // selectedCheckpoint → .checkpoint(id), 아니면 기존 규칙
  /// 선택이 가리키는 revision ID('현재 구성'은 nil). 비교 메뉴 판단에 쓴다.
  func revisionID(of selection: Selection) -> UUID?
  func select(_ selection: Selection) async     // .checkpoint 분기 추가
  /// 저장 직후 부른다. 목록을 불러온 뒤면 더하고(병합이 자리를 정한다), 아직이면 무시한다(open()이 읽는다).
  func add(checkpoint: CheckpointSummary)
  func caption(checkpoint: CheckpointSummary) -> String          // "체크포인트 · #n · <timeText>"
  func accessibilityLabel(checkpoint: CheckpointSummary) -> String  // "체크포인트, <제목>, #n 구성, <timeText> 저장"
  func savedText(_ date: Date) -> String                          // "<dateTimeText> 저장"
  ```
  동작:
  - `open()`: 첫 묶음과 `store.checkpointSummaries(projectID:)`를 둘 다 읽고, 어느 하나라도 실패하면 `listFailed = true`(둘 다 성공해야 `isLoaded`).
  - `entries`: `HistoryTimeline.merge(revisions: rows.map(\.summary), checkpoints: checkpoints)`를 `Entry`로 바꾼다(`rows`를 `[UUID: Row]`로 찾아 `.revision(row)`). `sections`: `HistorySections.group(entries, recordedAt: { entry 시각 }, calendar:)`.
  - `select(.checkpoint(id))`: `selectionRequested?()` 먼저. `checkpoints.first { $0.id == id }` 없으면 return; 이미 `selectedCheckpoint?.id == id`면 return. `store.checkpoint(id)`(nil이면 `StoreReadError.notFound`), revision이 `selectedRevisionID`와 같으면 `selectedSnapshot`·`selectedSummary` 재사용, 아니면 `store.snapshot(revisionID:)`와 `rows.first { $0.id == revisionID }?.summary ?? store.revisionSummary(revisionID)`. 실패하면 `notice = .unreadableRevision`, 선택 그대로. 성공하면 `selectedRevisionID`·`selectedSnapshot`·`selectedSummary`·`selectedCheckpoint`를 바꾸고 `isCheckpointCollapsed = false`, `await selectionChanged?()`.
  - `select(.revision(id))`: `selectedCheckpoint != nil && id == selectedRevisionID`면 `selectedCheckpoint = nil`만 하고 return(구성·띠 그대로, `selectionChanged` 부르지 않음). 그 밖은 기존대로이되 성공 시 `selectedCheckpoint = nil`.
  - `select(.current)`: `guard selectedRevisionID != nil`은 그대로, 비울 때 `selectedCheckpoint = nil`.
  - `reset(boardID:)`: `checkpoints = []`, `selectedCheckpoint = nil`, `isCheckpointCollapsed = false`.
  - `lookUp`이 고르는 것은 revision 행이다(기존대로).
  - `HistoryTabView`: `section.rows` → `section.entries`로 바꾸고 `.revision(row)`만 그린다(체크포인트 행 View는 Task 5). `onAppear`의 묶음 트리거는 `entry.id == history.entries.last?.id`로 바꾼다.

- [ ] **Step 1: 실패하는 테스트 작성** — `CheckpointHistoryModelTests.swift`, `@MainActor @Suite("이력 탭의 체크포인트 행 (W22)")`

  fixture: `HistoryModelTests.opened`와 같은 방식. `struct RevisionSeed { sequence: Int; at: Date; damagedSnapshot = false; snapshot: ConfigurationSnapshot? = nil }`, `struct CheckpointSeed { id: UUID; sequence: Int; title: String; at: Date; note = ""; next = "" }`. `opened(_ directory:, revisions:, checkpoints:, clock: HistoryClock) async throws -> Opened`: `withStore`로 Board(`RecordFixtures.project`, 현재 = 가장 큰 순번)와 revision(`RevisionDraft`, 스냅샷은 `seed.snapshot ?? RecordFixtures.snapshot()`), 체크포인트(`CheckpointRecord(id:, revisionID: revisionID(sequence), title:, progressNote:, nextSteps:, createdAt:, attachments: [])`)를 심고 `damagedSnapshot`이면 `snapshotData`를 `"{"`로 손상. `BrowserHarness(directory:, clock:)`로 열고 `start()`·`select(board)`. `Opened`는 `model`, `history`, `names: [String]`(entries의 `"#n"`/제목), `open()`(= `selectInspectorTab(.history)`). 기본 시각: `now = localTime("2026-10-19 15:30:00")`, `yesterday(_ h:m)`·`today(_ h:m)` 헬퍼.

  - `@Test("[W22-history-row-shape] 체크포인트 행의 문구·VoiceOver 라벨은 제목·순번·시각을 담는다")` — revision 1…5(어제), 체크포인트 c1(#5, 오늘 15:05, "인증 1차") → `open()` → `entries.first == .checkpoint(c1 summary)`; `caption(checkpoint:) == "체크포인트 · #5 · 오후 3:05"`; `accessibilityLabel(checkpoint:) == "체크포인트, 인증 1차, #5 구성, 오후 3:05 저장"`; `savedText(c1.createdAt).hasSuffix(" 저장")`이고 `dateTimeText(c1.createdAt)`로 시작.
  - `@Test("[W22-history-row-order] 체크포인트 행은 저장 시각 자리에 끼어들고 날짜 구역은 행 자신의 시각을 따른다")` — revision 1…5 어제 10:00~14:00(한 시간 간격), c1(#5, 어제 18:00, "어제 메모"), c2(#5, 오늘 15:05, "오늘 메모") → `sections.count == 2`; 첫 구역 제목 "오늘 · 10월 19일", entries == ["오늘 메모"]; 둘째 구역 제목 "어제 · 10월 18일", names == ["어제 메모", "#5", "#4", "#3", "#2", "#1"].
  - `@Test("[W22-history-old-revision-new-checkpoint] 오래된 revision에 나중에 저장한 체크포인트는 자기 시각 자리에 온다")` — revision 1…5 어제, c1(#2, 오늘 15:05, "오늘 저장") → names == ["오늘 저장", "#5", "#4", "#3", "#2", "#1"], 오늘 구역에 "오늘 저장"만, #2 행은 어제 구역.
  - `@Test("[W22-history-no-count-on-revision-rows] revision 행 문구에는 체크포인트 수가 없다")` — c1·c2 둘 다 #5 → `row(5)`의 `caption(row) == "#5 · 오후 2:00"`, `accessibilityLabel(row)`에 "체크포인트"가 없음, `Row`에 체크포인트 수 필드가 없다(컴파일 수준; 단언은 caption·label).
  - `@Test("[W22-history-paging-keeps-rows] 불러온 범위보다 오래된 체크포인트는 첫 묶음에서 맨 아래, 다음 묶음 뒤에는 자기 자리에 한 번만 있다")` — revision 1…60(어제부터 분 단위로 증가, 순번 순서대로), c1(#60, 순번 60 뒤 1분, "최신"), c2(#2, 순번 59와 60 사이, "오래된 revision의 메모"), c3(#2, 순번 2와 3 사이, "당시 메모") → `open()` → `history.rows.map(sequence) == 60…11`; names 첫 셋 == ["최신", "#60", "오래된 revision의 메모"], names.last == "당시 메모", `entries.last?.id == c3.id`; `loadMore()`(View의 트리거가 마지막 entry에서 부른다는 전제의 모델 호출) → names가 "#3", "당시 메모", "#2", "#1"로 끝남; "당시 메모"·"오래된 revision의 메모"가 각각 한 번; `rows.count == 60`.
  - `@Test("[W22-history-paging-keeps-rows] 목록을 불러오기 전에 더한 체크포인트는 무시되고 열 때 한 번만 읽는다")` — Review Focus 5: `open()` 전에 `history.add(checkpoint: c1)` → `checkpoints.isEmpty`; `open()` 뒤 c1이 한 번; 다시 `add(checkpoint: c2)`(저장소에 없어도 됨) → entries에 c2가 자기 자리.
  - `@Test("[W22-history-paging-keeps-rows] 체크포인트 목록을 읽지 못하면 revision 목록 읽기 실패와 같은 상태다")` — F-W22-12: 체크포인트 레코드의 revision을 가리키는 `revisionID`를 손상시킬 수 없으므로 `RevisionModel.cause`를 "rollback"으로 손상한 revision(`HistoryModelTests`의 `damagedCause` 방식)이 첫 묶음에 있게 해 `listFailed == true`임을 확인하고, 체크포인트가 있는 Board에서도 `checkpoints.isEmpty`·`entries.isEmpty`이며 현재 구성·편집(`canAddToBoard`)은 그대로임을 단언한다.
  - `@Test("[W22-select-current-revision-checkpoint] 현재 revision에 붙은 체크포인트를 고르면 과거 모드가 되고 선택은 체크포인트다", .tags(.A10))` — c1(#5) → `select(.checkpoint(c1))` → `selection == .checkpoint(c1)`, `selectedRevisionID == revisionID(5)`, `selectedSnapshot != nil`, `selectedCheckpoint?.title == "인증 1차"`, `model.isViewingPast`, `model.pastBannerDetail?.hasPrefix("#5 · ") == true`, `!model.canAddToBoard`, `!model.canSaveCheckpoint`.
  - `@Test("[W22-switch-to-revision-row] 체크포인트를 보다가 같은 revision 행을 고르면 선택만 revision으로 바뀌고 구성은 그대로다")` — `select(.checkpoint(c1))`, `let snapshot = selectedSnapshot` → `select(.revision(revisionID(5)))` → `selection == .revision(…)`, `selectedCheckpoint == nil`, `selectedSnapshot == snapshot`, `model.isViewingPast`.
  - `@Test("[W22-return-to-current] 체크포인트를 보다가 현재로 돌아가면 선택이 비고 띠·패널이 사라진다")` — `select(.checkpoint(c1))` → `model.returnToCurrent()` → `selection == .current`, `selectedCheckpoint == nil`, `!model.isViewingPast`, `model.checkpointPanel == nil`(Task 4 전에는 `history.selectedCheckpoint == nil`로 단언하고 Task 4에서 패널 단언을 더한다); 다시 `select(.checkpoint(c1))` 뒤 `select(.current)`도 같다.
  - `@Test("[W22-unreadable-revision-notice] 연결 revision의 구성을 읽을 수 없으면 선택을 바꾸지 않고 안내한다")` — revision 3 `damagedSnapshot`, c1(#3) → `select(.checkpoint(c1))` → `notice == .unreadableRevision`, `selection == .current`, `selectedCheckpoint == nil`, `!model.isViewingPast`; 저장소의 체크포인트 수 1 그대로.
  - `@Test("[W22-weblink-from-revision] 체크포인트가 가리키는 구성의 웹 링크 URL은 그 revision의 값이다")` — revision 3 스냅샷에 웹 링크 "명세" `https://example.com/spec`, revision 5 스냅샷에는 `https://example.com/spec-v2`(`SnapshotFixtures`로 만든 두 스냅샷), c1(#3) → `select(.checkpoint(c1))` → `selectedSnapshot?.node(named: "명세")?.url == "https://example.com/spec"`; `model.loadedSnapshot?.node(named: "명세")?.url == "https://example.com/spec-v2"`; `store.checkpoint(c1)`에는 URL 필드가 없다(레코드 필드 다섯 개만 비교).
  - `@Test("다른 Board를 고르면 체크포인트 목록·선택이 비워진다")` — Review Focus 3: 다른 Board(`RecordFixtures.otherProject`, revision 1)도 심고 `select(.checkpoint(c1))` 뒤 `model.select(otherBoard)` → `checkpoints.isEmpty`, `selectedCheckpoint == nil`, `selection == .current`, `!model.isViewingPast`.
  - `@Test("체크포인트 선택도 비교를 먼저 닫는다")` — `select(.revision(revisionID(4)))`, `model.compareWithCurrent()` → `select(.checkpoint(c1))` → `!model.isComparing`, `selection == .checkpoint(c1)`.

- [ ] **Step 2: 실패 확인** — Run: `UNIT CheckpointHistoryModelTests`. Expected: 컴파일 실패(`Selection.checkpoint` 없음).

- [ ] **Step 3: 구현** — Interfaces대로. `HistoryTabView`의 `Section.rows` 참조를 `entries`로 바꾸고 `.checkpoint`는 `EmptyView()`로 둔다(Task 5가 채운다).

- [ ] **Step 4: 통과 확인** — Run: `UNIT CheckpointHistoryModelTests`, 이어서 `UNIT HistoryModelTests`, `UNIT PastConfigurationModelTests`, `UNIT ComparisonModelTests`. Expected: 전부 통과.

- [ ] **Step 5: Commit**

```bash
git add Fianchetto/Features/BoardBrowser/HistoryPanelModel.swift Fianchetto/Features/BoardBrowser/HistoryTabView.swift \
  FianchettoTests/Features/CheckpointHistoryModelTests.swift
git commit -m "[History] List checkpoints as rows and select them as past configurations"
```
본문: 체크포인트 행은 Domain 병합으로 자리를 정하고, 고르면 W18 과거 모드와 같은 경로를 타며, 현재 revision의 체크포인트도 띠가 붙는다(디자인 확정)는 이유를 쓴다.

---

### Task 4: 화면 모델 — 저장 시트·켜짐 값·패널

**Obligations:** W22-file-menu-opens-sheet, W22-toolbar-opens-sheet, W22-entry-enablement, W22-open-read-failure, W22-blank-title-disables-save, W22-no-revision-while-typing, W22-cancel-discards-input, W22-sheet-keyboard-accessibility, W22-sheet-blocks-editing, W22-single-save-while-saving, W22-save-attaches-to-fixed-revision, W22-save-failure-keeps-input, W22-save-no-file-access, W22-history-updates-after-save, W22-select-shows-past-and-panel, W22-select-current-revision-checkpoint, W22-panel-omits-empty-columns, W22-panel-collapse, W22-compare-with-current-hides-panel, W22-compare-record-menu, W22-restore-is-separate, W22-icon-view-same-panel, W22-return-to-current

**Files:**
- Modify: `Fianchetto/Features/BoardBrowser/BoardBrowserModel.swift` (새 `// MARK: 체크포인트(W22)` 절, `canEditSelectedBoard`, `canCreateBoard`, `canArchiveSelected`, `canUnarchiveSelected`, `canReselectSelected`, `loadCurrent(of:)`, `canCompareRecord`, `compareRecord`, `LinkNotice`, `noticeTitle`, `noticeText`)
- Modify: `FianchettoTests/Features/BoardBrowserTestSupport.swift` (`BrowserHarness`에 `let serviceClock = TestClock(startingAt: date(0))`를 두고 기존 지역 `clock`을 그것으로 바꾼다)
- Create: `FianchettoTests/Features/CheckpointModelTests.swift`

**Interfaces:**
- Consumes: Task 2 `ConfigurationService.saveCheckpoint(title:progressNote:nextSteps:on:in:)`, `CheckpointOutcome`, `ProjectStore.currentRevisionSummary(projectID:)`; Task 3 `history.selectedCheckpoint`, `history.isCheckpointCollapsed`, `history.add(checkpoint:)`, `history.revisionID(of:)`, `history.savedText(_:)`, `Selection.checkpoint`; 기존 `ProjectName.normalize`, `history.dateTimeText`, `linkNotice`, `isViewingPast`, `isComparing`, `selectedBoardIsArchived`, `current`.
- Produces:
  ```swift
  /// 체크포인트 저장 시트의 입력(W22). nil이면 시트가 닫혀 있다. revision은 시트를 열 때 고정한다.
  struct CheckpointDraft: Equatable {
      var boardID: UUID
      var revisionID: UUID
      var sequence: Int
      var subtitle: String          // "현재 구성 · #6 · <기록 시각> 기록"
      var title = ""
      var progressNote = ""
      var nextSteps = ""
      var message: CheckpointMessage?
      var isSaving = false
  }
  enum CheckpointMessage: Equatable { case saveFailed }
  var checkpointDraft: CheckpointDraft?
  /// 파일 메뉴 '체크포인트 저장…'과 툴바 깃발이 켜지는 조건: Board를 골랐고 저장소가 열렸고 현재 구성을 읽었고, 보관·과거 보기·비교 중이 아니고,
  /// 어느 시트도 열려 있지 않다. 참이면 beginCheckpoint()가 읽기에 성공하는 한 반드시 시트를 연다.
  var canSaveCheckpoint: Bool
  /// 시트가 있고, 정리한 제목이 비어 있지 않고, 저장 중이 아니다.
  var canConfirmCheckpoint: Bool
  var canCancelCheckpoint: Bool
  /// 현재 revision 목록 정보를 한 번 읽어 고정하고 시트를 연다. 읽지 못하면 시트를 열지 않고 안내한다.
  func beginCheckpoint() async
  func cancelCheckpoint()
  func confirmCheckpoint() async
  /// 띠 아래 체크포인트 패널(W22). 체크포인트를 골랐고 비교 중이 아닐 때만 있다. 공백뿐인 열은 nil.
  struct CheckpointPanel: Equatable { var title: String; var savedText: String; var progressNote: String?; var nextSteps: String?; var isCollapsed: Bool }
  var checkpointPanel: CheckpointPanel?
  func toggleCheckpointPanel()
  var checkpointToggleHelp: String   // 접혀 있으면 "체크포인트 펴기", 아니면 "체크포인트 접기"
  ```
  - `LinkNotice.Kind`에 `/// 시트를 열 때 현재 revision 정보를 읽지 못했다(W22). case readFailed`, `Action`에 `case checkpoint`. `noticeTitle(.checkpoint) == "체크포인트 저장"`, `noticeText(.readFailed) == "기록을 불러오지 못했습니다"`(이력 탭과 같은 문구).
  - `private var hasOpenSheet: Bool` = `creation != nil || rename != nil || nodeForm != nil || moveDialog != nil || removal != nil || replacement != nil || restorePreview != nil || duplication != nil || checkpointDraft != nil`.
  - `canSaveCheckpoint`: `selectedBoardID != nil && openedStore != nil && !selectedBoardIsArchived && !isViewingPast && !isComparing && !hasOpenSheet`, `case .loaded = current`.
  - `canEditSelectedBoard`, `canCreateBoard`, `canArchiveSelected`, `canUnarchiveSelected`, `canReselectSelected`에 `checkpointDraft == nil`을 더한다. `canRefreshStatuses`, `canOpenSelected`, `canRevealSelected`, `canShowHistory`는 그대로.
  - `beginCheckpoint()`: `guard canSaveCheckpoint, let boardID = selectedBoardID, let store = openedStore?.store`. `do { guard let summary = try await store.currentRevisionSummary(projectID: boardID) else { throw StoreReadError.notFound(boardID) }; guard selectedBoardID == boardID, canSaveCheckpoint else { return }; checkpointDraft = CheckpointDraft(boardID:, revisionID: summary.id, sequence: summary.sequence, subtitle: String(localized: "현재 구성 · #\(summary.sequence) · \(history.dateTimeText(summary.recordedAt)) 기록")) } catch { guard selectedBoardID == boardID else { return }; linkNotice = LinkNotice(kind: .readFailed, request: nil, action: .checkpoint) }`.
  - `confirmCheckpoint()`: `guard canConfirmCheckpoint, var draft = checkpointDraft, let service = openedStore?.service`; `draft.isSaving = true; draft.message = nil; checkpointDraft = draft`; `service.saveCheckpoint(title: draft.title, progressNote: draft.progressNote, nextSteps: draft.nextSteps, on: draft.revisionID, in: draft.boardID)`. 던져지면 `finishCheckpoint(saving: draft, message: .saveFailed)`. `.saved(record)` → 저장하던 바로 그 시트일 때만(`checkpointDraft?.revisionID == draft.revisionID && boardID 같고 isSaving`) `checkpointDraft = nil`, `history.add(checkpoint: CheckpointSummary(id: record.id, revisionID: record.revisionID, sequence: draft.sequence, title: record.title, createdAt: record.createdAt))`. 화면은 현재 구성에 머문다(선택을 바꾸지 않는다). `.rejected` 전부 → `finishCheckpoint(saving:message: .saveFailed)`(입력 유지).
  - `cancelCheckpoint()`: `guard canCancelCheckpoint` → `checkpointDraft = nil`. `loadCurrent(of:)`에 `checkpointDraft = nil`.
  - `checkpointPanel`: `guard !isComparing, let record = history.selectedCheckpoint`. `progressNote`·`nextSteps`는 `trimmingCharacters(in: .whitespacesAndNewlines)`가 비면 nil, 아니면 원문. `savedText = history.savedText(record.createdAt)`, `isCollapsed = history.isCheckpointCollapsed`. `toggleCheckpointPanel()`: `history.isCheckpointCollapsed.toggle()`.
  - `canCompareRecord(_ row:)`: `guard selectedBoardID != nil, !isComparing`; `return history.revisionID(of: row) != history.revisionID(of: history.selection)`. `compareRecord`: `other`를 `history.revisionID(of: row).map(ComparisonTarget.revision) ?? .current`로 만든다(나머지 그대로).

- [ ] **Step 1: 실패하는 테스트 작성** — `CheckpointModelTests.swift`, `@MainActor @Suite("체크포인트 저장·조회 화면 흐름 (W22)")`

  fixture `opened(_ directory:, archived: Bool = false) async throws -> Opened`: `BrowserHarness` + `seedStore`. Task 2의 `seeded`와 같은 revision(1 Board "서비스 A", 2 Bishop 폴더 backend(`targets/backend/marker.txt`), 3 Wing 개발, 4 웹 링크 명세 spec(개발 아래), 5 Wing 문서, 6 URL spec-v2; 현재 6), 다른 Board "서비스 Z". `Opened`: `model`, `history`, `store`, `project`, `other`, `revisionID(_:)`, `revisionCount()`, `checkpointCount()`(`store.checkpointSummaries(projectID:).count`), `checkpoints(of sequence:)`, `targetFiles()`(marker 내용), `openHistory()`, `save(_ title: String, note: String = "", next: String = "") async`(= `beginCheckpoint()` → 필드 설정 → `confirmCheckpoint()`), `selectCheckpoint(_ title:) async throws`(entries에서 제목으로 찾아 `history.select(.checkpoint(id))`).

  - `@Test("[W22-file-menu-opens-sheet] 시작하면 현재 revision을 고정한 빈 시트가 열리고 아무것도 저장하지 않는다")` — `beginCheckpoint()` → `checkpointDraft?.revisionID == revisionID(6)`, `sequence == 6`, `subtitle.hasPrefix("현재 구성 · #6 · ")`, `subtitle.hasSuffix(" 기록")`, `title == ""`, `progressNote == ""`, `nextSteps == ""`, `message == nil`, `!canConfirmCheckpoint`, `canCancelCheckpoint`, `revisionCount() == 6`, `checkpointCount() == 0`.
  - `@Test("[W22-toolbar-opens-sheet] 툴바와 파일 메뉴는 같은 시작 동작을 쓴다")` — `canSaveCheckpoint == true`이면 `beginCheckpoint()`가 시트를 연다(툴바·메뉴 모두 `beginCheckpoint()`에 묶이는 것은 Task 5 View; 여기서는 두 번 연속 호출해도 시트가 하나이고 `canSaveCheckpoint`가 거짓이 됨을 단언).
  - `enum Situation: CaseIterable { case current, past, comparing, archived, noBoard, unreadableCurrent, createSheetOpen, checkpointSheetOpen }`
    `@Test("[W22-entry-enablement] 저장 명령은 편집할 수 있는 현재 구성을 볼 때만 켜진다", arguments: Situation.allCases)` — `current` 켜짐; `past`(`openHistory()` 뒤 `history.select(.revision(revisionID(4)))`) 꺼짐; `comparing`(past 뒤 `compareWithCurrent()`) 꺼짐; `archived`(`archived: true`) 꺼짐; `noBoard`(`select` 안 함; `BrowserHarness`를 Board 없이 `start()`) 꺼짐; `unreadableCurrent`(현재 revision `snapshotData` 손상 후 `select(project)` → `current == .unreadable`) 꺼짐; `createSheetOpen`(`beginCreate()`) 꺼짐; `checkpointSheetOpen`(`beginCheckpoint()`) 꺼짐. 켜진 경우 `beginCheckpoint()`가 시트를 열고, 꺼진 경우 `beginCheckpoint()` 뒤 `checkpointDraft`가 그 전과 같다.
  - `@Test("[W22-open-read-failure] 현재 revision 정보를 읽지 못하면 시트를 열지 않고 안내한다")` — `withStore(at: harness.url)`로 현재 revision의 `RevisionModel.cause`를 "rollback"으로 손상(`HistoryModelTests` 방식; `revisionSummary` 읽기가 `damagedRecord`로 실패) → `select(project)`는 스냅샷을 읽으므로 `current == .loaded`가 유지되는지 확인하고(아니면 손상을 `select` 뒤에 한다) `beginCheckpoint()` → `checkpointDraft == nil`, `linkNotice?.kind == .readFailed`, `linkNotice?.action == .checkpoint`, `noticeTitle(…) == "체크포인트 저장"`, `noticeText(…) == "기록을 불러오지 못했습니다"`, `revisionCount() == 6`, `checkpointCount() == 0`.
  - `@Test("[W22-blank-title-disables-save] 공백·줄바꿈뿐인 제목이면 확정이 꺼지고 호출해도 저장하지 않는다", arguments: ["   ", "\n\t", ""])` — `checkpointDraft?.title = 인수` → `!canConfirmCheckpoint`; `confirmCheckpoint()` → `checkpointCount() == 0`, `checkpointDraft != nil`, `message == nil`. (Review Focus 2)
  - `@Test("[W22-no-revision-while-typing] 입력 중에는 revision·현재 revision이 그대로이고 체크포인트도 없다", .tags(.A10))` — 제목·메모 입력 뒤 `revisionCount() == 6`, `store.project(project)?.currentRevisionID == revisionID(6)`, `checkpointCount() == 0`.
  - `@Test("[W22-cancel-discards-input] 취소하면 아무것도 저장하지 않고 다시 열면 비어 있다")` — 입력 뒤 `cancelCheckpoint()` → `checkpointDraft == nil`, `checkpointCount() == 0`, `revisionCount() == 6`, `!isViewingPast`; `beginCheckpoint()` → 세 필드가 "".
  - `@Test("[W22-sheet-keyboard-accessibility] 시트는 부제·세 입력·실패 문구 상태를 가진다")` — 값 확인(Return·Esc·VoiceOver 순서는 Task 5 UI 테스트). `canCancelCheckpoint == true`; 열린 동안 `canSaveCheckpoint == false`(재진입 없음).
  - `@Test("[W22-sheet-blocks-editing] 시트가 열린 동안 편집·Board 상태 변경·다시 선택은 꺼지고 조회 명령은 그대로이며 닫으면 돌아온다")` — Bishop "backend"를 고른 뒤 `before = (canAddToBoard, canRenameSelectedNode, canMoveSelected, canRemoveSelected, canRenameSelectedBoard, canArchiveSelected, canCreateBoard, canReselectSelected, canRefreshStatuses, canOpenSelected, canRevealSelected, canShowHistory)`; `beginCheckpoint()` → 앞 여덟 개 전부 false, `canRestoreShown == false`, `canDuplicateShown == false`, `canRefreshStatuses`·`canOpenSelected`·`canRevealSelected`·`canShowHistory`는 before와 같음; `beginCreate()` → `creation == nil`; `beginAddGroup()`·`beginRenameNode()`·`beginRemove()` → 각 시트 nil; `archiveSelected()` → 보관되지 않음; `cancelCheckpoint()` → 전부 before와 같음.
  - `@Test("[W22-single-save-while-saving] 확정을 연달아 두 번 요청해도 체크포인트는 하나만 생긴다")` — `checkpointDraft?.title = "한 번만"`; `async let a: Void = model.confirmCheckpoint(); async let b: Void = model.confirmCheckpoint(); _ = await (a, b)` → `checkpointCount() == 1`; 저장 중 `canConfirmCheckpoint == false`·`canCancelCheckpoint == false`는 `LoadGate` 없이 단언할 수 없으므로 첫 호출 직후 상태 대신 결과(하나)로 증명한다.
  - `@Test("[W22-save-attaches-to-fixed-revision] 확정하면 고정한 revision에 체크포인트가 붙고 revision은 늘지 않으며 화면은 현재 구성에 머문다", .tags(.A10))` — `openHistory()` 뒤 `save("인증 1차", note: "로그인 완료", next: "토큰 갱신")` → `checkpointDraft == nil`, `checkpoints(of: 6)`가 하나이고 제목·메모·다음 할 일 일치, `createdAt`이 `harness.serviceClock`이 낸 시각(저장 직전 `serviceClock.now()`를 한 번 더 부르면 안 되므로, 저장 뒤 `record.createdAt > 순번 6 recordedAt`이고 `record.createdAt == 저장 전 마지막 시각 + 1초`로 계산), `revisionCount() == 6`, `currentRevisionID == revisionID(6)`, `!isViewingPast`, `checkpointPanel == nil`, `canAddToBoard == true`, `history.selection == .current`, `history.entries.first`가 `.checkpoint`이고 제목 "인증 1차".
  - `@Test("[W22-history-updates-after-save] 이력 탭이 열린 채 저장하면 행이 더해지고 선택은 현재 구성에 남는다")` — `openHistory()`, `history.select(.current)`, `save("열린 채 저장")` → `history.entries.first == .checkpoint(…"열린 채 저장")`, `history.selection == .current`, `!isViewingPast`; `history.entries.count == 7`.
  - `@Test("[W22-save-failure-keeps-input] 저장이 실패하면 체크포인트가 생기지 않고 입력을 유지한 채 알리며 다시 시도할 수 있다")` — `harness.fault.failNext()`, `save("실패 뒤", note: "메모 유지", next: "할 일 유지")` → `checkpointCount() == 0`, `revisionCount() == 6`, `checkpointDraft?.title == "실패 뒤"`, `progressNote == "메모 유지"`, `nextSteps == "할 일 유지"`, `message == .saveFailed`, `isSaving == false`, `canConfirmCheckpoint`; `confirmCheckpoint()` → `checkpointCount() == 1`, `checkpointDraft == nil`.
  - `@Test("[W22-save-no-file-access] 저장은 파일 시스템 접근·접근 정보 해석·연결 대상 열기를 하지 않는다")` — `before = targetFiles()`, `resolutions = bookmarks.scopedResolutions.count`; `save("파일 접근 없음")` → `targetFiles() == before`, `bookmarks.scopedResolutions.count == resolutions`, `launcher.opened.isEmpty`, `launcher.revealed.isEmpty`.
  - `@Test("[W22-select-shows-past-and-panel] 체크포인트 행을 고르면 과거 구성·띠·패널이 보이고 고른 항목 카드는 유지된다", .tags(.A10))` — 순번 4를 골라… 아니다: 시트는 현재 구성에서만 열리므로 revision 4에 붙은 체크포인트는 `withStore`로 직접 심는다(`CheckpointRecord(id: fixedID(7101), revisionID: revisionID(4), title: "명세 확정", progressNote: "명세 링크 정리함", nextSteps: "문서 Wing 만들기", createdAt: date(5000))`). `openHistory()`, `selectCheckpoint("명세 확정")` → `isViewingPast`, `pastBannerDetail?.hasPrefix("#4 · ")`, `!canAddToBoard`, `checkpointPanel == CheckpointPanel(title: "명세 확정", savedText: history.savedText(date(5000)), progressNote: "명세 링크 정리함", nextSteps: "문서 Wing 만들기", isCollapsed: false)`, `history.selection == .checkpoint(fixedID(7101))`; `selectNode(명세)` → `pastItemCard?.url == "https://example.com/spec"`; `revisionCount() == 6`.
  - `@Test("[W22-select-current-revision-checkpoint] 현재 revision에 붙은 체크포인트를 골라도 과거 모드와 패널이 보이고 저장 명령은 꺼진다", .tags(.A10))` — `save("지금 구성")`, `openHistory()`, `selectCheckpoint("지금 구성")` → `isViewingPast`, `pastBannerDetail?.hasPrefix("#6 · ")`, `checkpointPanel?.title == "지금 구성"`, `history.selection != .current`, `!canSaveCheckpoint`, `!canAddToBoard`.
  - `@Test("[W22-panel-omits-empty-columns] 패널은 공백뿐인 열을 빼고 둘 다 비면 제목만 둔다")` — `save("메모만", note: "진행 중", next: "")`, `save("제목만", note: "", next: "   ")` → "메모만" 선택: `progressNote == "진행 중"`, `nextSteps == nil`; "제목만": 둘 다 nil, `title == "제목만"`.
  - `@Test("[W22-panel-collapse] 접기는 화면 상태이고 다른 체크포인트를 고르면 펴진다")` — "첫째"(note "첫째 메모")·"둘째"(note "둘째 메모") 저장, "첫째" 선택 → `toggleCheckpointPanel()` → `checkpointPanel?.isCollapsed == true`, `checkpointToggleHelp == "체크포인트 펴기"`, `revisionCount() == 6`, `checkpointCount() == 2`; "둘째" 선택 → `isCollapsed == false`, `progressNote == "둘째 메모"`, `checkpointToggleHelp == "체크포인트 접기"`.
  - `@Test("[W22-compare-with-current-hides-panel] 비교 중에는 패널이 없고 닫으면 돌아오며 비교 중 다른 체크포인트를 고르면 비교가 닫힌다")` — 순번 4 체크포인트 "명세 확정"(직접 심음)과 순번 5 체크포인트 "문서 추가"(직접 심음). "명세 확정" 선택 → `compareWithCurrent()` → `isComparing`, `checkpointPanel == nil`; `closeComparison()` → `checkpointPanel?.title == "명세 확정"`, `history.selection == .checkpoint(…)`; `compareWithCurrent()` 다시 → `selectCheckpoint("문서 추가")` → `!isComparing`, `pastBannerDetail?.hasPrefix("#5 · ")`, `checkpointPanel?.title == "문서 추가"`.
  - `@Test("[W22-compare-record-menu] 체크포인트 행의 '이 기록과 비교'는 그 revision 행과 같다")` — 순번 4 체크포인트 c; 현재 구성에서 `canCompareRecord(.checkpoint(c))` → true; `compareRecord(.checkpoint(c))` → `isComparing`, `comparison.before == .revision(revisionID(4))`·`after == .current`(ComparisonModel이 노출하는 대상 속성 이름을 따른다); `closeComparison()`; `history.select(.revision(revisionID(4)))` → `canCompareRecord(.checkpoint(c)) == false`; `selectCheckpoint`로 c 선택 → `canCompareRecord(.revision(revisionID(4))) == false`, `canCompareRecord(.revision(revisionID(5))) == true`, `canCompareRecord(.checkpoint(c)) == false`.
  - `@Test("[W22-restore-is-separate] 체크포인트 보기에서 복원하면 새 revision이 생기고 체크포인트는 원래 revision에 남는다")` — 순번 4 체크포인트 "명세 확정" 선택 → `canRestoreShown`, `beginRestore()`, `confirmRestore()` → `revisionCount() == 7`, 순번 7 `cause == .restored(from: revisionID(4))`, `checkpoints(of: 4).count == 1`, `checkpoints(of: 7).isEmpty`, `!isViewingPast`, `checkpointPanel == nil`.
  - `@Test("[W22-icon-view-same-panel] 아이콘 보기에서도 체크포인트를 고르면 같은 띠와 패널이다")` — `showIcons()` → 순번 4 체크포인트 선택 → `viewMode == .icons`, `isViewingPast`, `checkpointPanel?.title == "명세 확정"`, `!canAddToBoard`.
  - `@Test("[W22-return-to-current] 띠와 현재 구성 행으로 돌아가면 패널이 사라진다")` — 선택 뒤 `returnToCurrent()` → `checkpointPanel == nil`, `!isViewingPast`; 다시 선택 뒤 `history.select(.current)` → 같음.
  - `@Test("시트를 연 채 다른 Board를 고르면 시트가 닫히고 뒤늦은 저장은 쓰이지 않는다")` — Review Focus 1: `beginCheckpoint()` → `select(other)` → `checkpointDraft == nil`; `confirmCheckpoint()` → `checkpointCount() == 0`.
  - `@Test("체크포인트를 고른 채 이력 탭을 닫아도 띠와 패널이 이어진다")` — Review Focus 4: 선택 뒤 `selectInspectorTab(.item)` → `isViewingPast`, `checkpointPanel != nil`.

- [ ] **Step 2: 실패 확인** — Run: `UNIT CheckpointModelTests`. Expected: 컴파일 실패(`checkpointDraft` 등 없음).

- [ ] **Step 3: 구현** — Interfaces대로. `BrowserHarness.serviceClock`을 먼저 노출한다.

- [ ] **Step 4: 통과 확인** — Run: `UNIT CheckpointModelTests`, 이어서 `UNIT CheckpointHistoryModelTests`, `UNIT MenuCapabilityModelTests`, `UNIT RestoreModelTests`, `UNIT DuplicateModelTests`, `UNIT PastConfigurationModelTests`, `UNIT ComparisonModelTests`. Expected: 전부 통과.

- [ ] **Step 5: Commit**

```bash
git add Fianchetto/Features/BoardBrowser/BoardBrowserModel.swift FianchettoTests/Features/BoardBrowserTestSupport.swift \
  FianchettoTests/Features/CheckpointModelTests.swift
git commit -m "[Checkpoint] Add the save sheet flow and panel state to the browser model"
```
본문: 시트는 여는 순간 현재 revision을 한 번 읽어 고정하고 열린 동안 구성 편집을 막으며(PRD §6-G), 저장은 revision을 만들지 않고 화면은 현재 구성에 머문다는 이유를 쓴다.

---

### Task 5: 시트·패널·행·메뉴·문구와 전체 검증

**Obligations:** W22-file-menu-placement, W22-toolbar-opens-sheet, W22-file-menu-opens-sheet, W22-sheet-keyboard-accessibility, W22-history-row-shape, W22-select-shows-past-and-panel, W22-panel-collapse

**Files:**
- Create: `Fianchetto/Features/BoardBrowser/CheckpointSheet.swift`
- Create: `Fianchetto/Features/BoardBrowser/CheckpointPanelView.swift`
- Modify: `Fianchetto/Features/BoardBrowser/HistoryTabView.swift` (체크포인트 행 View, 오른쪽 클릭 메뉴)
- Modify: `Fianchetto/Features/BoardBrowser/BoardBrowserView.swift` (툴바 깃발, 패널 배치, `.sheet` 연결)
- Modify: `Fianchetto/App/BoardCommands.swift` (파일 메뉴)
- Modify: `Fianchetto/Localizable.xcstrings`, `scripts/check-terms.sh`
- Modify: `FianchettoUITests/BoardBrowserUITests.swift`

**Interfaces:**
- Consumes: Task 4 `checkpointDraft`, `canSaveCheckpoint`, `canConfirmCheckpoint`, `canCancelCheckpoint`, `beginCheckpoint()`, `cancelCheckpoint()`, `confirmCheckpoint()`, `checkpointPanel`, `toggleCheckpointPanel()`, `checkpointToggleHelp`; Task 3 `Entry.checkpoint`, `Selection.checkpoint`, `caption(checkpoint:)`, `accessibilityLabel(checkpoint:)`, `entries`.
- Produces: 접근성 식별자(Global Constraints 목록); 메뉴 항목 `체크포인트 저장…`; 툴바 버튼(`flag`, 도움말 `체크포인트 저장`).

- [ ] **Step 0: 디자인 문서 대조** — Run: `direnv exec . gh pr diff 64 -- docs/DESIGN.md`. 16장 체크포인트 절의 간격·글꼴·색 토큰·식별자를 읽고, 이 계획의 문구·식별자와 다른 점이 있으면 디자인 세션(`fianchetto-design`)에 `SendMessage`로 묻고 답을 받은 뒤 진행한다(obligation의 문구는 명세가 우선이고 시각 세부는 DESIGN이 우선).

- [ ] **Step 1: UI 테스트 작성** — `BoardBrowserUITests.swift`에 추가(호스트에서 실행하지 않는다)

  ```swift
  // [W22-file-menu-placement] [W22-file-menu-opens-sheet] [W22-toolbar-opens-sheet] [W22-sheet-keyboard-accessibility]
  // [W22-history-row-shape] [W22-select-shows-past-and-panel] [W22-panel-collapse]
  // 파일 메뉴 '체크포인트 저장…'은 '상태 새로고침' 뒤 구분선 다음, '이 구성으로 복원…' 앞에 있고, 툴바 깃발과 같은 시트를 연다.
  // 제목 칸의 Return은 저장, Esc는 취소. 저장한 체크포인트 행을 고르면 과거 구성 띠와 패널이 보이고 접기 버튼은 본문만 숨긴다.
  @MainActor
  func test_W22_saveAndViewCheckpoint()
  ```
  흐름(`test_W21_createBoardFromPastConfiguration`의 앞부분과 같다): Board "Plan"(⌘N) → 파일 › 'Wing 추가…'로 "Dev"(순번 2) →
  1. 파일 메뉴를 열고 `app.menuBars.menuBarItems["파일"].menuItems.allElementsBoundByIndex.map(\.title)`에서 `"상태 새로고침"`, `"체크포인트 저장…"`, `"이 구성으로 복원…"`의 index가 이 순서이고, '상태 새로고침'과 '체크포인트 저장…' 사이, '체크포인트 저장…'과 '이 구성으로 복원…' 사이에 각각 구분선(title이 빈 항목)이 정확히 하나씩 있다(W22-file-menu-placement). '체크포인트 저장…'이 켜져 있다. Esc로 닫는다.
  2. 파일 › '체크포인트 저장…' 클릭 → `checkpoint-sheet-title` 대기, `text(of:) == "체크포인트 저장"`; 시트 안 부제 staticText가 "현재 구성 · #2 · "로 시작; `checkpoint-title-field`가 초점(값 "")이고 `checkpoint-save`가 꺼져 있음.
  3. `app.typeText("First")`(초점이 제목 칸이므로 바로 입력) → `checkpoint-save` 켜짐; `checkpoint-memo-field`를 클릭해 "memo line"을 입력하고 Return을 눌러 줄바꿈 → 시트가 여전히 열려 있음(메모 칸의 Return은 줄바꿈); `checkpoint-title-field` 클릭 → Return → 시트가 사라짐(제목 칸의 Return은 저장).
  4. 보기 › '이력 보기' → `checkpoint-row-First` 대기; `label.hasPrefix("체크포인트, First, #2 구성, ")`(W22-history-row-shape); 클릭 → `past-banner` 대기, 띠 라벨에 "#2"가 있음; `checkpoint-panel` 대기, 그 안에 staticText "First"와 "memo line"이 있음(W22-select-shows-past-and-panel); `checkpoint-toolbar`가 꺼져 있음(과거 모드).
  5. `checkpoint-panel-toggle` 클릭 → "memo line"이 사라지고 "First"는 남음; 다시 클릭 → "memo line"이 돌아옴(W22-panel-collapse).
  6. `return-to-current` 클릭 → `past-banner`·`checkpoint-panel`이 사라짐.
  7. `checkpoint-toolbar` 클릭 → `checkpoint-sheet-title` 대기(W22-toolbar-opens-sheet); 툴바 순서: `checkpoint-toolbar.frame.minX > app.buttons["Wing 추가"].frame.minX`이고 `< history-toggle.frame.minX`(둘 다 존재할 때만 비교); Esc → 시트가 사라지고 `checkpoint-row-First`만 있다(저장 안 됨).
  기존 헬퍼(`UITestApp`, `text(of:)`)를 그대로 쓴다.

- [ ] **Step 2: 시트 View** — `CheckpointSheet.swift`

  `struct CheckpointSheet: View { @Bindable var model: BoardBrowserModel; @FocusState private var titleFocused: Bool }`. `VStack(alignment: .leading, spacing: 12)`, `.padding()`, `.frame(width: 480)`:
  - `Text("체크포인트 저장").font(.headline).accessibilityIdentifier("checkpoint-sheet-title")`
  - `Text(model.checkpointDraft?.subtitle ?? "").font(.callout).foregroundStyle(.secondary).monospacedDigit()`
  - `Text("제목").font(.callout)`(라벨은 칸 위, PR #64 16.6) + `TextField("제목", text: binding(\.title), prompt: Text("예: 인증 리팩토링 1차 완료")).labelsHidden().textFieldStyle(.roundedBorder).focused($titleFocused).onSubmit { if model.canConfirmCheckpoint { confirm() } }.accessibilityIdentifier("checkpoint-title-field")`
  - `Text("진행 메모").font(.callout)` 라벨 + `TextEditor(text: binding(\.progressNote)).frame(height: 92).font(.body).accessibilityIdentifier("checkpoint-memo-field")` — 입력 영역은 PR #64 16.6대로 텍스트 바탕(`textBackgroundColor`)에 구분선 색 테두리, 모서리 5
  - `Text("다음 할 일").font(.callout)` 라벨 + `TextEditor(text: binding(\.nextSteps)).frame(height: 72).accessibilityIdentifier("checkpoint-next-field")`
  - `Text("저장한 체크포인트는 고칠 수 없습니다. 고치려면 같은 구성에 새로 저장합니다.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)`
  - `if model.checkpointDraft?.message == .saveFailed { Label("저장하지 못했습니다. 입력한 내용은 그대로 있으니 다시 시도하세요.", systemImage: "exclamationmark.triangle").font(.callout).accessibilityIdentifier("checkpoint-save-error") }`
  - `HStack { Spacer(); Button("취소", role: .cancel) { model.cancelCheckpoint() }.keyboardShortcut(.cancelAction).disabled(!model.canCancelCheckpoint).accessibilityIdentifier("checkpoint-cancel"); Button("저장") { confirm() }.keyboardShortcut(.defaultAction).disabled(!model.canConfirmCheckpoint).accessibilityIdentifier("checkpoint-save") }`
  - `.onAppear { titleFocused = true }`; `binding(_ keyPath:)`는 `Binding(get: { model.checkpointDraft?[keyPath: keyPath] ?? "" }, set: { model.checkpointDraft?[keyPath: keyPath] = $0 })`.
  - TextEditor 안의 Return이 `.defaultAction`을 눌러 저장해 버리면(VM UI 테스트 3단계가 잡는다) '저장'의 `.keyboardShortcut(.defaultAction)`을 빼고 제목 칸 `onSubmit`만 남긴다. 시트 안 입력 영역은 라벨과 `accessibilityElement(children: .contain)`으로 묶어 VoiceOver가 제목·부제·제목 칸·진행 메모·다음 할 일·안내 순서로 읽게 한다.

- [ ] **Step 3: 패널 View** — `CheckpointPanelView.swift`

  `struct CheckpointPanelView: View { let model: BoardBrowserModel; let panel: BoardBrowserModel.CheckpointPanel }`:
  - `VStack(alignment: .leading, spacing: 8)`: 머리 `HStack`: `Image(systemName: "flag.fill")` + `Text(panel.title).font(.headline)` + `Text(panel.savedText).font(.caption).foregroundStyle(.secondary).monospacedDigit()` + `Spacer()` + `Button { model.toggleCheckpointPanel() } label: { Image(systemName: panel.isCollapsed ? "chevron.down" : "chevron.up") }.buttonStyle(.borderless).help(model.checkpointToggleHelp).accessibilityLabel(model.checkpointToggleHelp).accessibilityIdentifier("checkpoint-panel-toggle")`.
  - `if !panel.isCollapsed { ScrollView { HStack(alignment: .top, spacing: 16) { column("진행 메모", panel.progressNote); column("다음 할 일", panel.nextSteps) } } .frame(maxHeight: 200) }` — `column`은 값이 nil이면 `EmptyView`, 아니면 `VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption).foregroundStyle(.secondary); Text(body).font(.callout).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading)`.
  - `.padding(8)`, 위아래 `Divider()`, 바탕은 PR #64 16.6의 텍스트 바탕(`textBackgroundColor`), `.accessibilityIdentifier("checkpoint-panel")`.
  - `ConfigurationTreeView`: `PastConfigurationBanner` 바로 아래에 `if let panel = model.checkpointPanel { CheckpointPanelView(model: model, panel: panel) }`(비교 중 분기 밖, 과거 모드 분기 안).

- [ ] **Step 4: 이력 행, 툴바, 메뉴, 시트 연결**

  `HistoryTabView`: `ForEach(section.entries)`에서 `.checkpoint(summary)` → `CheckpointRowView(history: history, summary: summary, isSelected: selection == .checkpoint(summary.id)).tag(HistoryPanelModel.Selection.checkpoint(summary.id)).contextMenu { compareMenu(.checkpoint(summary.id)) }.id(summary.id)` + 묶음 트리거 `onAppear`(마지막 entry). `CheckpointRowView`: `HStack(alignment: .firstTextBaseline, spacing: 8) { Image(systemName: "flag.fill").frame(width: 16).foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.themeAccentText)); VStack(alignment: .leading, spacing: 2) { Text(summary.title).fontWeight(.medium); Text(history.caption(checkpoint: summary)).font(.caption).foregroundStyle(.secondary).monospacedDigit() } }.accessibilityElement(children: .ignore).accessibilityLabel(history.accessibilityLabel(checkpoint: summary)).accessibilityIdentifier("checkpoint-row-\(summary.title)")`. 색 심볼 이름은 Asset Catalog의 `ThemeAccentText` 생성 심볼을 기존 코드(`grep -rn themeAccent Fianchetto`)대로 쓴다.
  `ConfigurationTreeView`의 `ToolbarItemGroup`: 'Wing 추가' 뒤에 `Button { Task { await model.beginCheckpoint() } } label: { Label("체크포인트 저장", systemImage: "flag") }.help("체크포인트 저장").disabled(!model.canSaveCheckpoint).accessibilityIdentifier("checkpoint-toolbar")`. VM UI 테스트 7단계가 순서(Wing 추가 < 깃발 < 이력)를 못 맞추면 `BoardBrowserView`의 `history-toggle` `ToolbarItem(placement: .primaryAction)` 바로 앞에 같은 placement로 옮긴다.
  `BoardBrowserView`: 복제 시트 다음에 `.sheet(isPresented: Binding(get: { model.checkpointDraft != nil }, set: { if !$0 { model.cancelCheckpoint() } })) { CheckpointSheet(model: model) }`.
  `BoardCommands`의 `CommandGroup(replacing: .newItem)`: `Button("상태 새로고침")` 다음 기존 `Divider()` 뒤에 `Button("체크포인트 저장…") { Task { await model?.beginCheckpoint() } }.disabled(!isEnabled(\.canSaveCheckpoint))`와 새 `Divider()`를 넣고, 그다음이 `이 구성으로 복원…`이 되게 한다. 단축키 없음.

- [ ] **Step 5: 문구와 용어 검사**

  `Localizable.xcstrings`에 기존 항목과 같은 형식(`comment`, `extractionState: manual`, Xcode 서식 `" : "`)으로 없는 것만 더한다. comment "체크포인트 저장 시트(W22)." / "이력 탭 체크포인트 행(W22)." / "체크포인트 패널(W22).": `체크포인트 저장…`, `체크포인트 저장`, `현재 구성 · #%lld · %@ 기록`, `제목`, `진행 메모`, `다음 할 일`, `예: 인증 리팩토링 1차 완료`, `저장한 체크포인트는 고칠 수 없습니다. 고치려면 같은 구성에 새로 저장합니다.`, `저장`, `저장하지 못했습니다. 입력한 내용은 그대로 있으니 다시 시도하세요.`, `체크포인트 · #%lld · %@`, `체크포인트, %@, #%lld 구성, %@ 저장`, `%@ 저장`, `체크포인트 접기`, `체크포인트 펴기`.
  `scripts/check-terms.sh`의 `REQUIRED`에 `"체크포인트 저장…" "체크포인트 저장" "진행 메모" "다음 할 일" "체크포인트 접기" "체크포인트 펴기" "체크포인트 · #%lld · %@"`를 더하고 첫 줄 주석에 `W22-catalog(체크포인트 시트·행·패널 문구)`를 붙인다.
  Run: `scripts/check-terms.sh && scripts/check-structure.sh && scripts/tests/check-scripts-test.sh`. Expected: 모두 OK.

- [ ] **Step 6: 빌드와 단위 테스트** — Run: `UNIT ALL`. Expected: 전부 통과, 경고 0개. UI 테스트 target은 이 명령으로 컴파일된다(실행은 건너뛴다).

- [ ] **Step 7: 디자인 세션에 알린 뒤 호스트 전체 검증(UI 제외)** — `SendMessage`로 `fianchetto-design`에 "호스트 verify 시작"을 알린다. Run: `SKIP_UI_TESTS=1 scripts/verify.sh`. Expected: 통과. TileIconSnapshotTests 라이트 2장 불일치만 실패하면 '알려진 호스트 드리프트'로 적고 다음 단계로 간다(그 밖의 실패는 고친다).

- [ ] **Step 8: 가상 머신에서 UI 테스트 포함 전체 검증** — 디자인 세션에 "VM 사용 시작"을 알린다. Run: `scripts/vm-verify.sh`. Expected: 통과(`test_W22_saveAndViewCheckpoint` 포함). 가상 머신을 시작할 수 없거나 스크립트가 환경 문제로 실패하면 출력 그대로 보고하고 `DONE_WITH_CONCERNS`로 끝낸다. **호스트에서 XCUITest를 실행하는 것으로 대신하지 않는다.** 끝나면 VM 사용 종료를 알리고 `pgrep -fl "Fianchetto.app/Contents/MacOS/Fianchetto"`로 남은 앱이 없는지 확인한다.

- [ ] **Step 9: Commit**

```bash
git add Fianchetto/Features/BoardBrowser/CheckpointSheet.swift Fianchetto/Features/BoardBrowser/CheckpointPanelView.swift \
  Fianchetto/Features/BoardBrowser/HistoryTabView.swift Fianchetto/Features/BoardBrowser/BoardBrowserView.swift \
  Fianchetto/App/BoardCommands.swift Fianchetto/Localizable.xcstrings scripts/check-terms.sh \
  FianchettoUITests/BoardBrowserUITests.swift
git commit -m "[Checkpoint] Add the save sheet, history rows, panel and File menu command"
```
본문: 파일 메뉴(0018·0035 선례)와 툴바 깃발에서 같은 시트를 열고, 체크포인트 행·패널은 디자인 세션이 확정한 시안(1A·2A·3B, PR #64)을 따르며, 키보드 동작은 가상 머신의 UI 테스트로 확인했다(또는 확인하지 못했다)는 사실을 쓴다.

---

## 계획 이후

- `/spec-cycle:verify W22` — obligation 커버리지 확인과 `done` 기록. `superpowers:finishing-a-development-branch`보다 먼저 한다.
- PR 본문: 요약, 게이트 run `t-w22-72ee8b76`(결정 기록 없음), 검증(VM 결과·호스트 결과·알려진 드리프트), 미검증 항목(macOS 15 실기), 비평 note(로그 원문 금지는 구현 리뷰 항목 — PR 본문에 "로그에 체크포인트 ID·순번만 남김"을 적는다). 병합은 디자인 세션이 VM 캡처(라이트·다크) 확인 뒤 한다. 디자인 문서 PR #64는 이 PR 뒤에 병합한다(디자인 세션이 식별자를 대조해 11장 이동을 더한다).
- macOS 15 실기 확인은 이 계획의 범위가 아니다(W27). `verify.sh` 통과를 macOS 15 통과로 보고하지 않는다.
