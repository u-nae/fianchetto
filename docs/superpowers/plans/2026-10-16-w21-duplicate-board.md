# W21 과거 구성에서 새 Board 만들기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 과거 구성 띠의 '이 구성으로…' › '새 Board 만들기…'와 파일 메뉴 '이 구성으로 새 Board 만들기…'로 이름 시트를 열고, 확정하면 그 revision 구성의 복사본(새 Board ID·새 Node ID, 참조 레코드는 공유)으로 origin이 기록된 새 Board를 만들어 선택한다.

**Architecture:** ID 재매핑은 Domain의 순수 함수(`ConfigurationDuplicator`)가 한다. 원본 Board·revision 확인과 새 Project + 순번 1 revision 커밋은 `ProjectStore` actor 안에서 한 저장 단위로 한다(결정표 `duplicate_request_outcome`, W20 복원과 같은 모양). 화면 모델은 시트 상태(`Duplication`)와 시작·취소·확정만 맡고, 확정 뒤에는 기존 `select(_:)`로 새 Board를 고른다(W07 Board 만들기와 같은 흐름).

**Tech Stack:** Swift 6(strict concurrency), SwiftUI, SwiftData, Swift Testing(단위), XCUITest(핵심 흐름 1개), `xcodebuild`.

**Spec:** `.spec-gate/runs/t-w21-bcfe30da/spec-brief.md` (READY handoff `tdd-handoff.yaml`의 렌더. 명세 게이트가 brainstorming을 대신했다). 결정 기록 `docs/decisions/0036-duplicate-shares-reference-records.md`(참조 레코드 공유), 선례 `0034`, `0035`, `0009`. 디자인 문서는 PR #62(`docs/DESIGN.md` 16.3 '새 Board 만들기 시트', 16.5 식별자)가 담당하므로 이 계획은 DESIGN.md를 고치지 않는다. 프로젝트 규칙은 `CLAUDE.md`.

## Global Constraints

- 작업 브랜치 `feature/w21-duplicate-board`(저장소 `/Users/unae/Documents/u.naee/fianchetto`, 기반 `main` bc21a6e, 이미 만들어져 있다). 기본 브랜치에 직접 커밋하지 않는다.
- **모든 테스트의 이름 또는 태그에 그 테스트가 증명하는 obligation_id를 포함한다.** 형식은 `@Test("[W21-…] 동작 서술")`. XCUITest는 함수 바로 위 주석에 `// [W21-…]`를 적는다. `/spec-cycle:verify`가 `FianchettoTests/**`와 `FianchettoUITests/**`에서 이 문자열을 찾는다.
- A09를 증명하는 테스트에는 `.tags(.A09)`를 붙인다(`AcceptanceTags.swift`에 `A09` 추가).
- 의존 방향: `Features → Services → Domain`, `Persistence`는 Domain 값 타입만 밖으로 낸다. Domain은 `Foundation`만 import한다. 앱 target에 외부 패키지를 더하지 않는다.
- 새 Board의 Node는 원본 revision이 기록한 참조 ID를 그대로 쓰고 새 `ResourceReferenceRecord`를 만들지 않는다(0036). 종류·표시 이름·형제 순서·URL·아이콘(purpose)·당시 경로(recordedPath)는 그대로 복사한다. 원본 Board의 revision·체크포인트·보관 상태를 바꾸지 않는다. 연결 대상 원본과 북마크에 접근하지 않는다.
- 새 Board: 새 Project ID, `origin = ProjectOrigin(kind: .duplicate, sourceProjectID:, sourceRevisionID:)`, `archivedAt = nil`, 순번 1 revision `cause == .duplicated`, 복원 출처 없음, `createdAt`과 순번 1 `recordedAt`은 확정 시각(`now()` 한 번), 이름은 정리한 입력 이름. 체크포인트는 복사하지 않는다.
- 원본 스냅샷을 읽지 못하면 빈 구성으로 새 Board를 만들지 않는다. 보관된 원본 Board에서도 만든다(PRD §6-C, 0009).
- 상태 확인(접근 정보 해석)은 W15 규칙대로 항목 선택·열기·명시적 새로고침 때만 일어난다. 만들기 자체는 해석하지 않는다.
- 화면 문구는 한국어이고 String Catalog(`Fianchetto/Localizable.xcstrings`)에 `extractionState: manual`로 넣는다(Xcode 서식 `" : "`). 화면에 DB·JSON·bookmark·'그룹'·'파일 삭제'를 쓰지 않는다. 코드 식별자는 중립 용어(Project, Node, Revision, duplicate)를 쓴다.
- 메뉴 제목: 띠 메뉴 `새 Board 만들기…`('복원…' 다음), 파일 메뉴 `이 구성으로 새 Board 만들기…`('이 구성으로 복원…' 바로 아래, 단축키 없음). 시트 문구(PR #62 확정): 제목 `#n 구성으로 새 Board 만들기`, 부제 `<당시 Board 이름> · #n · <기록 시각>`, 필드 `Board 이름` 기본값 `<당시 Board 이름> 사본` 전체 선택, 안내 `새 Board는 이 구성으로 시작하고 이력은 새로 쌓입니다. 원래 Board는 바뀌지 않습니다.`, 버튼 `취소`(Esc)·`만들기`(Return, 기본). 저장 실패 문구는 기존 `저장하지 못했습니다. 다시 시도하세요.`.
- 접근성 식별자: `duplicate-sheet-title`, `duplicate-name-field`, `duplicate-cancel`, `duplicate-confirm`. 띠 메뉴는 기존 `restore-menu`.
- 테스트: Persistence·Service는 임시 디렉터리의 실제 SwiftData 저장소(`ServiceHarness`, `BrowserHarness`)를 쓰고 mock으로 대체하지 않는다. 저장 실패는 `FaultPoint.failNext()`로 주입한다. sleep·무작위 데이터 금지. 임시 디렉터리는 `withTemporaryDirectoryAsync`가 정리한다.
- 단위 테스트 실행(호스트, 화면을 막지 않음):
  ```sh
  xcodebuild -project Fianchetto.xcodeproj -scheme Fianchetto -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Fianchetto-verify \
    test -skip-testing:FianchettoUITests -only-testing:FianchettoTests/<SuiteTypeName>
  ```
  아래에서 `UNIT <Suite>`는 이 명령을 뜻한다. `UNIT ALL`은 `-only-testing`을 뺀 것이다.
- **XCUITest를 호스트에서 실행하지 않는다**(키보드·마우스를 가져간다). UI 테스트는 `scripts/vm-verify.sh`(Tart 가상 머신 `fianchetto-ui`)로만 실행한다. 호스트 전체 검증·VM 사용 전에 디자인 세션(`fianchetto-design`)에 알린다. 호스트 `SKIP_UI_TESTS=1 scripts/verify.sh`는 알려진 스냅샷 드리프트(TileIconSnapshotTests 라이트 2장)로 실패할 수 있다. 그 실패는 이 변경과 무관하므로 출력과 함께 보고하고 VM 결과를 기준으로 한다.
- 경고 0개(Swift 6 strict concurrency). `scripts/verify.sh`가 검사한다.
- 커밋 메시지: `[Area] Imperative subject`(영어, 대문자 시작, 마침표 없음, ≤72자), 본문은 왜를 72자 줄바꿈으로, 마지막 줄 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- `BoardBrowserModel.swift`는 이미 1,870줄이다. 만들기 흐름(약 70줄)은 그 파일의 새 `// MARK: 과거 구성에서 새 Board 만들기(W21)` 절에 둔다. 파일 분리는 이 계획의 범위가 아니다.

## Review Focus

1. **시트를 연 채 다른 Board를 고른다** — 시트가 닫혀야 하고, 뒤늦은 확정이 쓰이면 안 된다. (Task 3 테스트)
2. **'만들기'를 연달아 두 번 누른다** — Board는 하나만 생겨야 한다. (Task 3 테스트, obligation W21-single-confirm-while-saving)
3. **켜진 메뉴가 아무 일도 하지 않는 경우** — `canDuplicateShown`이 참이면 `beginDuplicate()`가 반드시 시트를 연다(MenuCapability 원칙). (Task 3 테스트)
4. **원본 구성이 섞인 순서로 저장되어 있다** — 재매핑은 `sortIndex`를 그대로 복사하므로 트리 순서가 같아야 한다. (Task 1 테스트)
5. **새 Board의 이름 필드에 당시 이름이 아니라 현재 이름이 들어가는 회귀** — 부제와 기본값은 원본 revision의 `projectName`이다. (Task 3 테스트)

---

## 파일 구조

| 경로 | 책임 | task |
| --- | --- | --- |
| `Fianchetto/Domain/ConfigurationDuplicator.swift` | 새 이름·새 Node ID·부모 재매핑의 순수 함수 | 1 |
| `FianchettoTests/Domain/ConfigurationDuplicatorTests.swift` | 재매핑 구조·ID·불변 | 1 |
| `FianchettoTests/Domain/AcceptanceTags.swift` | `A09` 태그 | 1 |
| `Fianchetto/Persistence/ProjectStore.swift` | 원본 Board·revision을 actor 안에서 읽고 새 Project + 순번 1을 한 저장 단위로 커밋 | 2 |
| `Fianchetto/Services/ConfigurationService.swift` | `duplicateProject(from:of:named:)`와 순수 판정 `decideDuplicate` | 2 |
| `FianchettoTests/Services/DuplicateServiceTests.swift` | 결정표 32칸, 서비스 시나리오 | 2 |
| `Fianchetto/Features/BoardBrowser/BoardBrowserModel.swift` | 시트 상태, 켜짐 값, 시작·취소·확정 | 3 |
| `FianchettoTests/Features/DuplicateModelTests.swift` | 화면 모델 흐름 | 3 |
| `Fianchetto/Features/BoardBrowser/DuplicateSheet.swift` | 시트 View | 4 |
| `Fianchetto/Features/BoardBrowser/BoardBrowserView.swift` | 띠 메뉴 항목, `.sheet` 연결 | 4 |
| `Fianchetto/App/BoardCommands.swift` | 파일 메뉴 '이 구성으로 새 Board 만들기…' | 4 |
| `Fianchetto/Localizable.xcstrings`, `scripts/check-terms.sh` | 문구, 용어 검사 | 4 |
| `FianchettoUITests/BoardBrowserUITests.swift` | 핵심 흐름 UI 테스트 1개 | 4 |

---

### Task 1: Domain ID 재매핑

**Obligations:** W21-remap-preserves-structure, W21-remap-leaves-source, W21-new-ids-remapped

**Files:**
- Create: `Fianchetto/Domain/ConfigurationDuplicator.swift`
- Modify: `FianchettoTests/Domain/AcceptanceTags.swift` (`@Tag static var A09: Self` 추가)
- Create: `FianchettoTests/Domain/ConfigurationDuplicatorTests.swift`

**Interfaces:**
- Consumes: `ConfigurationSnapshot`, `ConfigurationNode`, `SnapshotValidator.violations(in:)`, 테스트 지원 `SnapshotFixtures`, `SequentialIDs`, `fixedID`.
- Produces:
  ```swift
  // ConfigurationDuplicator.swift — Foundation만 import.
  /// 과거 구성의 복사본(W21, PRD §6-F): Board 이름을 바꾸고 모든 Node에 새 UUID를 주며 부모 관계를 새 ID로 재매핑한다.
  /// 종류·표시 이름·형제 순서·URL·아이콘·참조 ID·당시 경로는 그대로다(0036: 참조 레코드는 원본과 공유).
  /// ID는 `nodes` 배열 순서대로 `makeID()`를 한 번씩 불러 정한다. 디스크·시간을 읽지 않는다.
  enum ConfigurationDuplicator {
      static func duplicate(_ snapshot: ConfigurationSnapshot, projectName: String, makeID: () -> UUID) -> ConfigurationSnapshot
  }
  ```
  원본에 없는 부모 ID(깨진 참조)는 재매핑 대상이 없으므로 그대로 둔다(원본이 검사기를 통과하면 생기지 않는다).

- [ ] **Step 0: 게이트 산출물 커밋**

```bash
cd /Users/unae/Documents/u.naee/fianchetto
git add .spec-gate/runs/t-w21-bcfe30da docs/decisions/0036-duplicate-shares-reference-records.md \
  docs/work-items.yaml docs/superpowers/plans/2026-10-16-w21-duplicate-board.md
git commit -m "[Spec] Record W21 gate handoff, decision 0036 and plan"
```
본문에 "W21 duplicate-board passed the specification gate (run t-w21-bcfe30da); keep the handoff, brief, decision 0036 and the plan with the code they justify."를 쓰고 Co-Authored-By 줄을 붙인다. `.gitignore`가 중간 산출물(normalized·manifest·critic)을 빼는지 `git status`로 확인한다. 빠지지 않으면(기존 run들처럼 추적된다면) 그대로 둔다.

- [ ] **Step 1: 실패하는 테스트 작성** — `ConfigurationDuplicatorTests.swift`, `@Suite("과거 구성 복사: ID 재매핑 (W21)")`

  fixture(네 가지, `enum Shape: CaseIterable, CustomTestStringConvertible { case empty, singleBishop, nested, shuffled }`):
  - `empty`: `ConfigurationSnapshot(projectName: "원본", nodes: [])`
  - `singleBishop`: 최상위 Bishop 폴더 `backend`(참조 `fixedID(102)`, 경로 `/dev/api`) 하나.
  - `nested`: Wing "개발"(0) › Wing "서버"(0) › 웹 링크 "명세"(0, `https://example.com/spec`)와 Bishop 파일 "notes.md"(1, 참조 `fixedID(103)`, 경로 `/docs/notes.md`, `purpose: "document"`); 최상위에 Wing "문서"(1).
  - `shuffled`: 최상위 형제 다섯 개(Wing·Bishop·웹 링크 섞어)를 `sortIndex` 4,0,3,1,2 순서로 `nodes` 배열에 넣는다.

  헬퍼 `structure(_ s: ConfigurationSnapshot) -> [[String]]`: 각 Node를 `[kind, displayName, 부모 displayName ?? "", sortIndex, url ?? "", purpose ?? "", referenceID?.uuidString ?? "", recordedPath ?? ""]`로 바꿔 (부모 이름, sortIndex)로 정렬한 배열. ID를 뺀 구조 비교에 쓴다.

  - `@Test("[W21-remap-preserves-structure] 복사본은 구조를 보존하고 새 ID만 쓰며 검사기를 통과한다", .tags(.A09), arguments: Shape.allCases)`
    ```swift
    let source = Shape.snapshot(shape)
    let ids = SequentialIDs()
    let copy = ConfigurationDuplicator.duplicate(source, projectName: "복사본", makeID: ids.next)
    #expect(copy.projectName == "복사본")
    #expect(copy.nodes.count == source.nodes.count)
    #expect(Set(copy.nodes.map(\.id)) == Set(ids.issued))
    #expect(Set(copy.nodes.map(\.id)).isDisjoint(with: source.nodes.map(\.id)))
    #expect(structure(copy) == structure(source))
    #expect(SnapshotValidator.violations(in: copy).isEmpty)
    // 부모는 원본 부모에 대응하는 새 ID
    for (old, new) in zip(source.nodes, copy.nodes) {
        let expectedParent = old.parentID.map { oldParent in copy.nodes[source.nodes.firstIndex { $0.id == oldParent }!].id }
        #expect(new.parentID == expectedParent)
        #expect(new.referenceID == old.referenceID)
        #expect(new.recordedPath == old.recordedPath)
    }
    let again = ConfigurationDuplicator.duplicate(source, projectName: "복사본", makeID: SequentialIDs().next)
    #expect(again == copy)
    ```
  - `@Test("[W21-remap-leaves-source] 재매핑은 원본 구성을 바꾸지 않는다")` — `nested`의 복사 전 값을 `let before = source`로 잡고 복사 뒤 `#expect(source == before)`, `source.nodes.map(\.id)`·`map(\.parentID)`·`map(\.sortIndex)`가 그대로.
  - `@Test("[W21-new-ids-remapped] 복사본의 ID는 원본 어느 Node와도 겹치지 않고 부모는 새 ID다", .tags(.A09))` — `nested`에서 "명세"·"notes.md"의 새 부모가 복사본의 "서버" ID이고, "서버"의 새 부모가 복사본의 "개발" ID, 복사본 ID 집합과 원본 ID 집합의 교집합이 비어 있다.

- [ ] **Step 2: 실패 확인** — Run: `UNIT ConfigurationDuplicatorTests`. Expected: 컴파일 실패(`ConfigurationDuplicator` 없음, `.A09` 없음).

- [ ] **Step 3: 구현** — `ConfigurationDuplicator.duplicate(_:projectName:makeID:)`

  `nodes` 순서대로 `mapping[old.id] = makeID()`를 만든 뒤, 각 Node를 복사해 `id = mapping[old.id]!`, `parentID = old.parentID.flatMap { mapping[$0] } ?? old.parentID`로 바꾼다. 나머지 필드는 그대로. `A09` 태그를 더한다.

- [ ] **Step 4: 통과 확인** — Run: `UNIT ConfigurationDuplicatorTests`. Expected: 전부 통과.

- [ ] **Step 5: Commit**

```bash
git add Fianchetto/Domain/ConfigurationDuplicator.swift FianchettoTests/Domain/ConfigurationDuplicatorTests.swift \
  FianchettoTests/Domain/AcceptanceTags.swift
git commit -m "[Domain] Duplicate a configuration with remapped node IDs"
```
본문: 새 Board가 원본과 ID를 공유하지 않도록(불변식 1·2, A09) 재매핑을 순수 함수로 두었고 참조 ID는 0036에 따라 그대로 둔다는 이유를 쓴다.

---

### Task 2: 저장소 커밋과 서비스 판정

**Obligations:** W21-service-outcome-table, W21-service-atomic-commit, W21-service-rejects-foreign-revision, W21-service-source-unreadable, W21-service-allows-archived-source, W21-duplicate_request_outcome-R1, W21-duplicate_request_outcome-R2, W21-duplicate_request_outcome-R3, W21-duplicate_request_outcome-R4, W21-duplicate_request_outcome-R5, W21-origin-recorded, W21-source-preserved, W21-independent-editing, W21-replace-target-independent, W21-shares-reference-records, W21-duplicate-chain, W21-name-trimmed, W21-new-ids-remapped

**Files:**
- Modify: `Fianchetto/Persistence/ProjectStore.swift`
- Modify: `Fianchetto/Services/ConfigurationService.swift`
- Create: `FianchettoTests/Services/DuplicateServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 `ConfigurationDuplicator.duplicate(_:projectName:makeID:)`; 기존 `RestoreTarget`, `ProjectStore.readRestoreTarget(_:projectID:)`(private, 재사용), `StoreAdapter.insert(_ project:)`, `ProjectStore.insert(_:projectID:sequence:)`(private), `commit()`, `ProjectName.normalize`, `ProjectOrigin`, `RevisionCause.duplicated`; 테스트 지원 `ServiceHarness`, `makeBoard`, `FaultPoint`, `TestIDs`, `TestClock`, `withStore(at:)`, `copyStoreFiles(from:to:)`, `withTemporaryDirectoryAsync`, `TargetFiles`, `TargetReplacementService`, `LinkingService`.
- Produces:
  ```swift
  // ProjectStore.swift
  /// 복제 원본을 저장소에서 읽은 결과. revision 읽기 결과는 복원과 같은 네 경우(RestoreTarget)다.
  enum DuplicationSource: Sendable {
      case projectNotFound
      case found(ProjectRecord, RestoreTarget)
  }
  enum DuplicationDecision<Skip: Sendable>: Sendable {
      case create(ProjectRecord, first: RevisionAppend)
      case skip(Skip)
  }
  enum DuplicationResult<Skip: Sendable>: Sendable {
      case created(RevisionSummary, RevisionAppend)
      case skipped(Skip)
  }
  /// 원본 Board와 revision을 같은 actor 안에서 읽어 `decide`에 주고, 만들기로 하면 새 Project와 순번 1 revision을 한 저장 단위로 커밋한다.
  func createProject<Skip: Sendable>(
      copying sourceRevisionID: UUID, of sourceProjectID: UUID,
      decide: @Sendable (DuplicationSource) -> DuplicationDecision<Skip>
  ) throws(ProjectStoreError) -> DuplicationResult<Skip>

  // ConfigurationService.swift
  /// 과거 revision의 구성으로 새 Board를 만든다. 결정표 duplicate_request_outcome.
  func duplicateProject(from revisionID: UUID, of sourceProjectID: UUID, named name: String)
      async throws(ConfigurationServiceError) -> ConfigurationCommitOutcome
  /// 순서(FIRST): 이름 → 원본 Board → 원본 revision(없음·다른 Board / 읽기 실패) → 생성. 보관 상태는 읽지 않는다.
  static func decideDuplicate(named name: String, source: DuplicationSource, now: () -> Date, makeID: () -> UUID)
      -> DuplicationDecision<Decision>
  ```
  결과 대응(결정표 outcome → 서비스 결과): `rejected_blank_name` → `.rejected(.blankName)`, `rejected_project_not_found` → `.rejected(.projectNotFound)`, `rejected_revision_not_found` → `.rejected(.revisionNotFound)`, `error_source_unreadable` → `throw .targetConfigurationUnreadable`, `created` → `.committed(summary, snapshot)`(`summary.projectID`가 새 Board). `ProjectStoreError`는 기존 `map`으로 `.saveFailed`/`.storeUnavailable`.
  `.create`가 만드는 값의 순서: `let recordedAt = now()` 한 번 → `projectID = makeID()` → `revisionID = makeID()` → `ConfigurationDuplicator.duplicate(snapshot, projectName: 정리한 이름, makeID: makeID)`. `ProjectRecord(id: projectID, createdAt: recordedAt, currentRevisionID: revisionID, archivedAt: nil, origin: ProjectOrigin(kind: .duplicate, sourceProjectID: sourceProjectID, sourceRevisionID: summary.id))`, `RevisionAppend(id: revisionID, recordedAt: recordedAt, cause: .duplicated, snapshot: copy, references: [])`.

- [ ] **Step 1: 결정표 테스트 작성(실패)** — `DuplicateServiceTests.swift`, `@Suite("과거 구성에서 새 Board 만들기 서비스 (W21)")`

  순수 판정 `ConfigurationService.decideDuplicate`를 결정표 32칸으로 검사한다. 칸은 테스트 파일 안에 정적 표로 둔다(spec-brief §4의 32행을 그대로 옮긴다. `RestoreServiceTests`의 `Cell`·`classify` 구조를 따른다).

  ```swift
  enum Outcome: String, Sendable { case rejectedBlankName, rejectedProjectNotFound, rejectedRevisionNotFound, errorSourceUnreadable, created }
  enum Revision: String, Sendable { case found, notFound, otherBoard, unreadable }
  struct Cell: Sendable, CustomTestStringConvertible {
      var rule: String; var blankName: Bool; var projectFound: Bool; var revision: Revision; var archived: Bool; var expected: Outcome
  }
  static let cells: [Cell]   // 32개: R1 16, R2 8, R3 4, R4 2, R5 2
  static func source(_ cell: Cell) -> DuplicationSource   // projectFound가 거짓이면 .projectNotFound, 아니면 .found(archivedAt: cell.archived ? date(5) : nil, RestoreTarget)
  static func classify(_ decision: DuplicationDecision<ConfigurationService.Decision>) -> Outcome
  ```
  `classify`는 `.create(project, first)`일 때 `project.origin == ProjectOrigin(kind: .duplicate, sourceProjectID: sourceProjectID, sourceRevisionID: sourceSummary.id)`, `project.archivedAt == nil`, `project.currentRevisionID == first.id`, `project.createdAt == first.recordedAt`, `first.cause == .duplicated`, `first.references.isEmpty`, `first.snapshot.projectName == "알파 2차"`, `first.snapshot.nodes.count == sourceSnapshot.nodes.count`, `Set(first.snapshot.nodes.map(\.id)).isDisjoint(with: sourceSnapshot.nodes.map(\.id))`를 함께 단언한다. 이름 입력은 `blankName ? "   " : "  알파 2차  "`.

  테스트(규칙마다 하나, `arguments: cells.filter { $0.rule == "R1" }` 식):
  - `@Test("[W21-duplicate_request_outcome-R1] 정리한 이름이 비면 다른 입력과 무관하게 거부한다")`
  - `@Test("[W21-duplicate_request_outcome-R2] 원본 Board가 없으면 거부한다")`
  - `@Test("[W21-duplicate_request_outcome-R3] 원본 revision이 없거나 다른 Board면 거부한다")`
  - `@Test("[W21-duplicate_request_outcome-R4] 원본 revision의 구성을 읽을 수 없으면 원본 읽기 오류다")`
  - `@Test("[W21-duplicate_request_outcome-R5] 원본 revision을 읽었으면 보관 여부와 무관하게 새 Board를 만든다")`
  - `@Test("[W21-service-outcome-table] 판정은 결정표와 같고 created일 때만 Project와 revision을 만든다")` — 32칸 전부에서 `classify(decision) == expected`이고 `.create`인 칸이 정확히 `expected == .created`인 칸(2개)임을 단언한다.

- [ ] **Step 2: 실패 확인** — Run: `UNIT DuplicateServiceTests`. Expected: 컴파일 실패(`decideDuplicate`, `DuplicationSource` 없음).

- [ ] **Step 3: 구현**

  `ProjectStore.createProject(copying:of:decide:)`: `adapter.project(sourceProjectID)`가 nil → `.projectNotFound`, 던지면 `throw .storeUnavailable`; 있으면 `readRestoreTarget(sourceRevisionID, projectID: sourceProjectID)`로 `.found(project, target)`. `decide` 결과가 `.skip`이면 `.skipped`. `.create(project, first)`면 `adapter.insert(project)`와 `insert(first, projectID: project.id, sequence: 1)`을 하고(실패 시 `modelContext.rollback()` 후 `throw .storeUnavailable`), `try commit()`, `.created(Self.summary(first, projectID: project.id, sequence: 1), first)`.

  `decideDuplicate`: `ProjectName.normalize(name)` 실패 → `.skip(.outcome(.rejected(.blankName)))` → `source`가 `.projectNotFound` → `.skip(.outcome(.rejected(.projectNotFound)))` → `RestoreTarget`이 `.notFound`·`.otherProject` → `.skip(.outcome(.rejected(.revisionNotFound)))`, `.unreadable` → `.skip(.unreadableTarget)` → `.found(summary, snapshot)` → 위 Interfaces의 순서로 `.create`.

  `duplicateProject(from:of:named:)`는 `restore(_:in:)`와 같은 모양으로 `store.createProject(copying:of:decide:)`를 부르고 결과를 대응표대로 돌려준다(`.skipped(.unreadableCurrent)`는 이 경로에서 나오지 않지만 switch 완전성을 위해 `throw .currentConfigurationUnreadable`로 둔다).

- [ ] **Step 4: 통과 확인** — Run: `UNIT DuplicateServiceTests`. Expected: Step 1의 테스트 전부 통과.

- [ ] **Step 5: 서비스 시나리오 테스트 작성(실패)**

  공용 fixture `seeded(_ directory:, mutate:) async throws -> Seeded`(`RestoreServiceTests.seeded`와 같은 방식, `Seeded`에 `other`·`ids`·`url`·`checkpointTitles`·`snapshot(_:)`·`summaries()`·`count()`·`projectCount()`(= `store.projects().count`)·`revisionIDs(of:)`): ① `makeBoard(_, "서비스 알파")` ② `linking.link`로 Bishop 폴더 `backend`(대상 `targets/legacy/backend`, 참조 R1) ③ `TargetReplacementService`로 대상을 `targets/v2/backend`(참조 R2)로 교체 ④ `.addGroup(name: "문서")` ⑤ `.addGroup(name: "개발")` ⑥ `.addWebLink(name: "명세", url: "https://example.com/spec", parentID: 개발)` ⑦ `linking.link`로 Bishop 파일 `notes.md`(`targets/docs/notes.md`, 참조 R3, parentID: 개발) ⑧ `.changePurpose(notes.md, "document")` ⑨ `.renameProject("서비스 A")`. 순번은 1…9, 현재 순번 9, 참조 레코드 3개. **원본 revision은 순번 8**(이름 "서비스 알파", 항목 전부 있음)을 쓴다. 명세 Background의 순번 4는 실제 편집으로 만들 수 없어(비평 F-W21-13) 순번 8로 옮긴 것이며 단언 내용은 같다. 다른 Board "서비스 B"(order)도 하나 만든다. 새 Board를 만드는 헬퍼 `dup(_ s: Seeded, from sequence: Int = 8, named: String = "서비스 C") async throws -> (summary: RevisionSummary, snapshot: ConfigurationSnapshot)`.

  - `@Test("[W21-origin-recorded] 새 Board는 원본 Board와 revision을 출처로 기록하고 보관되어 있지 않다")` — `dup` 뒤 `store.project(summary.projectID)`의 `origin == ProjectOrigin(kind: .duplicate, sourceProjectID: s.project, sourceRevisionID: s.revisionID(8))`, `archivedAt == nil`, `currentRevisionID == summary.id`, `createdAt == summary.recordedAt`; `summary.sequence == 1`, `summary.cause == .duplicated`, `summary.projectName == "서비스 C"`, `summary.recordedAt == date(1000)`(새 서비스의 시계 시작값) ≠ 순번 8의 `recordedAt`; 새 Board의 revision 수 1.
  - `@Test("[W21-new-ids-remapped] 새 Board와 Node는 새 UUID를 쓰고 부모 관계는 새 ID로 재매핑된다", .tags(.A09))` — `summary.projectID != s.project`; 원본 순번 1…9 스냅샷의 모든 Node ID 집합과 새 스냅샷 ID 집합이 서로소; 새 스냅샷에서 "명세"·"notes.md"의 `parentID`가 새 "개발"의 id; 구조(종류·이름·부모 이름·순서·URL·purpose·referenceID·recordedPath)가 순번 8과 같다(Task 1의 `structure` 헬퍼를 이 파일에도 둔다).
  - `@Test("[W21-shares-reference-records] 새 Board의 항목은 원본 revision의 참조 레코드를 그대로 쓰고 새 참조를 만들지 않는다")` — 새 "backend"의 `referenceID == 순번 8 backend.referenceID`(R2), 새 "notes.md"의 `referenceID == R3`, `store.referenceCount() == 3`, 새 "backend"의 `recordedPath == 순번 8의 recordedPath`.
  - `@Test("[W21-source-preserved] 원본의 이력·체크포인트·현재 구성은 그대로이고 새 Board에는 체크포인트가 없다", .tags(.A09))` — 순번 3에 체크포인트 "1차 정리"를 넣은 저장소에서 `dup` 전후 `summaries()` 9개가 같고(원인·시각·이름), 각 스냅샷이 같고, 현재 revision ID가 그대로, `checkpointTitles(순번 3) == ["1차 정리"]`, 새 Board의 `checkpointTitles(summary.id).isEmpty`, `projectCount() == 3`.
  - `@Test("[W21-independent-editing] 만든 뒤 원본과 새 Board의 편집은 서로 영향을 주지 않는다", .tags(.A09))` — `dup` → 원본에 `.addGroup(name: "임시")`(순번 10) → 새 Board에 `.renameProject("서비스 C2")`(순번 2)와 "문서" `.remove`(순번 3) → 원본 현재 구성에 "문서"가 있고 이름 "서비스 A", 새 Board 현재 구성에 "임시"가 없고 "문서"도 없으며 이름 "서비스 C2"; 원본 revision 수 10, 새 Board 3.
  - `@Test("[W21-replace-target-independent] 새 Board에서 연결 대상을 바꾸면 새 참조가 생기고 원본의 참조는 그대로다")` — 새 Board의 "backend"를 `TargetReplacementService`로 `targets/v3/backend`로 교체 → 새 Board 현재 "backend"의 referenceID가 R2가 아니고, `referenceCount() == 4`, 원본 현재 구성과 순번 8의 "backend"는 R2 그대로.
  - `@Test("[W21-duplicate-chain] 복제로 만든 Board를 다시 복제하면 출처는 그 Board와 revision이다")` — `dup` → B; `duplicateProject(from: B 순번 1, of: B, named: "서비스 D")` → D의 origin이 `(duplicate, B, B 순번 1 ID)`, D의 Node ID가 원본·B 어느 ID와도 겹치지 않음, `projectCount() == 4`.
  - `@Test("[W21-name-trimmed] 이름의 앞뒤 공백은 정리되어 저장된다")` — `named: "  알파 2차  "` → `summary.projectName == "알파 2차"`, 스냅샷 `projectName == "알파 2차"`.
  - `@Test("[W21-service-allows-archived-source] 보관된 원본 Board의 요청은 거부되지 않고 새 Board는 보관되지 않는다")` — `store.setArchived(s.project, at: date(100))` → `dup` 성공, 새 Board `archivedAt == nil`, 원본 `archivedAt == date(100)` 그대로, 원본 revision 수 9.
  - `@Test("[W21-service-rejects-foreign-revision] 없는 revision이나 다른 Board의 revision은 거부된다", arguments: [true, false])` — 다른 Board의 revision ID / `fixedID(404)` → `.rejected(.revisionNotFound)`, `projectCount() == 2`.
  - `@Test("[W21-service-source-unreadable] 원본 revision의 구성을 읽을 수 없으면 오류이고 빈 구성으로 만들지 않는다")` — 순번 8의 `snapshotData`를 손상(`RestoreServiceTests.corrupt`와 같은 방법) → `#expect(throws: ConfigurationServiceError.targetConfigurationUnreadable)`, `projectCount() == 2`.
  - `@Test("[W21-service-atomic-commit] 저장이 실패하면 새 Project와 revision이 모두 남지 않고 참조 레코드도 그대로다")` — `fault.failNext()` → `#expect(throws: ConfigurationServiceError.saveFailed)`, `projectCount() == 2`, 원본 revision 수 9, `referenceCount() == 3`; 다시 `dup` → 성공, `projectCount() == 3`.
  - `@Test("[W21-duplicate_request_outcome-R1] 공백뿐인 이름은 저장소를 바꾸지 않고 거부된다")` — `named: "   "` → `.rejected(.blankName)`, `projectCount() == 2`.
  - `@Test("[W21-duplicate_request_outcome-R2] 없는 Board의 요청은 거부된다")` — `of: fixedID(404)` → `.rejected(.projectNotFound)`.

- [ ] **Step 6: 실패 확인 후 필요한 만큼 구현, 통과 확인** — Run: `UNIT DuplicateServiceTests`. Expected: 전부 통과.

- [ ] **Step 7: 전체 단위 테스트** — Run: `UNIT ALL`. Expected: 기존 테스트 포함 전부 통과, 새 경고 없음.

- [ ] **Step 8: Commit**

```bash
git add Fianchetto/Persistence/ProjectStore.swift Fianchetto/Services/ConfigurationService.swift \
  FianchettoTests/Services/DuplicateServiceTests.swift
git commit -m "[Duplicate] Create a board from a past revision inside the store actor"
```
본문: 원본 확인과 새 Project·순번 1 커밋을 한 저장 단위로 묶어(불변식 5) 결과가 커밋 시점 기준이 되게 했고, 참조 레코드는 0036에 따라 공유한다는 이유를 쓴다.

---

### Task 3: 화면 모델의 만들기 흐름

**Obligations:** W21-menu-opens-sheet, W21-archived-menu-enabled, W21-file-menu-enablement, W21-blank-name-disables-confirm, W21-cancel-keeps-past-view, W21-single-confirm-while-saving, W21-confirm-creates-board, W21-archived-source-allowed, W21-copies-unreachable-items, W21-no-disk-side-effects, W21-save-failure-keeps-input, W21-shared-access-info, W21-sheet-keyboard-accessibility

**Files:**
- Modify: `Fianchetto/Features/BoardBrowser/BoardBrowserModel.swift` (새 `// MARK: 과거 구성에서 새 Board 만들기(W21)` 절, `canRestoreShown`, `loadCurrent(of:)`)
- Create: `FianchettoTests/Features/DuplicateModelTests.swift`

**Interfaces:**
- Consumes: Task 2 `ConfigurationService.duplicateProject(from:of:named:)`, `CommitRejection.blankName`; 기존 `history.selectedSummary`, `history.selectedSnapshot`, `history.dateTimeText(_:)`, `isViewingPast`, `isComparing`, `restorePreview`, `select(_:)`, `reloadBoards()`, `ProjectName.normalize`; 테스트 지원 `BrowserHarness`, `seedStore`, `TargetFiles`, `ScriptedBookmarkSystem`, `RecordingLauncher`.
- Produces:
  ```swift
  /// 새 Board 만들기 시트의 입력(W21). nil이면 시트가 닫혀 있다.
  struct Duplication: Equatable {
      var sourceBoardID: UUID
      var revisionID: UUID
      var title: String        // "#8 구성으로 새 Board 만들기"
      var subtitle: String     // "서비스 알파 · #8 · <기록 시각>"
      var name: String         // 기본 "서비스 알파 사본"
      var message: CreationMessage?
      var isSaving = false
  }
  var duplication: Duplication?
  /// 띠 '새 Board 만들기…'와 파일 메뉴 '이 구성으로 새 Board 만들기…'가 켜지는 조건: 과거 구성을 보고 있고, 비교 중이 아니고,
  /// 만들기·복원 시트가 닫혀 있고, 고른 revision의 목록 정보와 스냅샷이 있다. 보관된 Board에서도 켜진다(0009). 참이면 beginDuplicate()가 반드시 시트를 연다.
  var canDuplicateShown: Bool
  /// 시트가 있고, 정리한 이름이 비어 있지 않고, 저장 중이 아니다.
  var canConfirmDuplicate: Bool
  /// 시트가 있고 저장 중이 아니다('취소' 켜짐).
  var canCancelDuplicate: Bool
  func beginDuplicate()
  func cancelDuplicate()
  func confirmDuplicate() async
  ```
  `canRestoreShown`에 `duplication == nil`을 더한다(만들기 시트가 열린 동안 '이 구성으로 복원…' 꺼짐). `loadCurrent(of:)`에서 `duplication = nil`.
  `beginDuplicate()`: `guard canDuplicateShown, let boardID = selectedBoardID, let summary = history.selectedSummary`; `title = String(localized: "#\(summary.sequence) 구성으로 새 Board 만들기")`, `subtitle = String(localized: "\(summary.projectName) · #\(summary.sequence) · \(history.dateTimeText(summary.recordedAt))")`, `name = String(localized: "\(summary.projectName) 사본")`. 저장소를 읽지 않는다.
  `confirmDuplicate()`: `guard canConfirmDuplicate, var draft = duplication, let service = openedStore?.service`; `draft.isSaving = true; draft.message = nil; duplication = draft`; `service.duplicateProject(from: draft.revisionID, of: draft.sourceBoardID, named: draft.name)`. `.committed(summary, _)` → 저장하던 바로 그 시트일 때만(`duplication?.revisionID == draft.revisionID && isSaving`) `duplication = nil`, `await reloadBoards()`, `await select(summary.projectID)`(새 Board 선택 → `loadCurrent`가 과거 모드·비교·시트 상태를 정리한다). `.rejected(.blankName)` → `message = .nameRequired`, `isSaving = false`(시트 유지). 그 밖의 거부·`.unchanged`·던져진 오류 → `message = .saveFailed`, `isSaving = false`(입력 유지). 시트가 그 사이 닫혔으면(다른 Board 선택) 아무것도 바꾸지 않는다.
  `cancelDuplicate()`: `guard canCancelDuplicate` → `duplication = nil`.

- [ ] **Step 1: 실패하는 테스트 작성** — `DuplicateModelTests.swift`, `@MainActor @Suite("과거 구성에서 새 Board 만들기 화면 흐름 (W21)")`

  fixture `opened(_ directory:, archived: Bool = false) async throws -> Opened`: `RestoreModelTests.opened`와 같은 방식(`BrowserHarness` + `seedStore`), revision은 Task 2 fixture와 같다(순번 1…9, 원본은 순번 8 "서비스 알파"), 다른 Board "서비스 B". 두 대상 폴더(`legacy`, `v2`)와 `targets/docs/notes.md`에 표식 내용을 둔다. `Opened`는 `viewPast(_ sequence:)`, `revisionCount(of:)`, `boardCount`(= `activeNames.count + archivedNames.count`), `targetFiles()`, `store`, `newBoard() -> ProjectListing?`(= `model.board(named: "서비스 알파 사본")`)를 제공한다.

  - `@Test("[W21-menu-opens-sheet] 과거 구성에서 만들기를 시작하면 이름 시트가 열리고 아무것도 저장하지 않는다")` — `viewPast(8)`, `beginDuplicate()` → `duplication?.title == "#8 구성으로 새 Board 만들기"`, `subtitle.hasPrefix("서비스 알파 · #8 · ")`, `name == "서비스 알파 사본"`(현재 이름 "서비스 A"가 아니다, Review Focus 5), `message == nil`, `canConfirmDuplicate`, `canCancelDuplicate`, `boardCount == 2`, revision 수 9.
  - `@Test("[W21-archived-menu-enabled] 보관된 Board의 과거 구성에서 만들기는 켜지고 복원은 꺼진다")` — `archived: true`, `viewPast(8)` → `canDuplicateShown == true`, `canRestoreShown == false`, `beginDuplicate()` 뒤 `duplication != nil`.
  - `enum Situation: CaseIterable { case current, past, comparing, archivedPast, duplicateSheetOpen, restoreSheetOpen }`
    `@Test("[W21-file-menu-enablement] 만들기 명령은 과거 구성을 볼 때만 켜지고 시트가 열려 있으면 꺼진다", arguments: Situation.allCases)` — `current` 꺼짐, `past` 켜짐, `comparing`(`compareWithCurrent()`) 꺼짐, `archivedPast` 켜짐, `duplicateSheetOpen`(`beginDuplicate()` 뒤) 꺼짐, `restoreSheetOpen`(`beginRestore()` 뒤) 꺼짐. 켜진 경우 `beginDuplicate()`가 시트를 열고(Review Focus 3), 꺼진 경우 `beginDuplicate()` 뒤 `duplication`이 그 전과 같다. `duplicateSheetOpen`에서는 `canRestoreShown == false`도 단언한다(양방향).
  - `@Test("[W21-blank-name-disables-confirm] 공백뿐인 이름이면 확정이 꺼지고 호출해도 만들지 않는다")` — `duplication?.name = "   "` → `canConfirmDuplicate == false`; `confirmDuplicate()` → `boardCount == 2`, `duplication != nil`, `message == nil`.
  - `@Test("[W21-cancel-keeps-past-view] 취소하면 아무것도 저장하지 않고 과거 구성 보기가 이어진다")` — `name = "버릴 이름"`, `cancelDuplicate()` → `duplication == nil`, `isViewingPast`, `history.selectedRevisionID == 순번 8 ID`, `selectedBoardID == project`, `boardCount == 2`, revision 수 9.
  - `@Test("[W21-sheet-keyboard-accessibility] 시트의 제목·부제·이름·안내 문구를 가진다")` — `title`, `subtitle`, `name` 값 확인(Esc·Return·VoiceOver 순서는 Task 4 UI 테스트가 증명). `canCancelDuplicate == true`.
  - `@Test("[W21-single-confirm-while-saving] 확정을 연달아 두 번 요청해도 Board는 하나만 생긴다")` — `async let a: Void = model.confirmDuplicate(); async let b: Void = model.confirmDuplicate(); _ = await (a, b)` → `boardCount == 3`, `activeNames.filter { $0 == "서비스 알파 사본" }.count == 1`. (Review Focus 2)
  - `@Test("[W21-confirm-creates-board] 확정하면 새 Board가 생겨 선택되고 현재 구성을 보인다", .tags(.A09))` — `duplication?.name = "서비스 C"`, `confirmDuplicate()` → `duplication == nil`, `activeNames == ["서비스 A", "서비스 B", "서비스 C"]`, `selectedBoardID == board(named: "서비스 C")?.id`, `!isViewingPast`, `!isComparing`, `history.selection == .current`, `loadedSnapshot?.projectName == "서비스 C"`, `loadedSnapshot`의 구조가 순번 8 스냅샷과 같다(이름 제외; `structure` 헬퍼), 새 Board revision 수 1, 그 summary의 `cause == .duplicated`, `recordedAt == 순번 8 recordedAt`이 아님, 원본 revision 수 9, `inspectorTab == .history`면 `history.rows.first`의 `causeText == "과거 구성에서 만듦"`.
  - `@Test("[W21-archived-source-allowed] 보관된 Board의 과거 구성으로 만든 새 Board는 보관되지 않은 채 선택된다")` — `archived: true` → `confirmDuplicate()` → `activeNames.contains("서비스 알파 사본")`, `archivedNames == ["서비스 A"]`, `selectedBoardID == newBoard()?.id`, 원본 revision 수 9.
  - `@Test("[W21-copies-unreachable-items] 접근할 수 없는 항목도 그대로 복사하고 만들기 동안 해석하지 않으며 상태는 고를 때 확인한다")` — `bookmarks.failResolution(with: NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError))`, `viewPast(8)`, `beginDuplicate()`, 해석 횟수 기록, `confirmDuplicate()` → 해석 횟수 그대로, 새 Board 현재 구성의 "backend"의 `referenceID == R2`(순번 8의 값) → `selectNode(backend)` → `displayedStatus(of:) == .missing`, `canReselectSelected`, `canRefreshStatuses`.
  - `@Test("[W21-no-disk-side-effects] 만들기는 연결 대상 원본을 읽거나 바꾸지 않는다")` — 만들기 전후 `targetFiles()`가 같고, `launcher.opened.isEmpty`, `launcher.revealed.isEmpty`, `actions.revealed.isEmpty`, `bookmarks.scopedResolutions.count` 변화 없음.
  - `@Test("[W21-save-failure-keeps-input] 저장이 실패하면 새 Board가 생기지 않고 시트는 입력을 유지한 채 알리며 다시 시도할 수 있다")` — `name = "서비스 C"`, `fault.failNext()`, `confirmDuplicate()` → `boardCount == 2`, `duplication?.name == "서비스 C"`, `message == .saveFailed`, `isSaving == false`, `canConfirmDuplicate`, `isViewingPast`, `history.selectedRevisionID == 순번 8 ID`; 다시 `confirmDuplicate()` → `activeNames.contains("서비스 C")`, `duplication == nil`.
  - `@Test("[W21-shared-access-info] 한쪽 Board에서 같은 대상의 접근 정보를 갱신하면 같은 참조를 쓰는 다른 Board에서도 보인다")` — `confirmDuplicate()`로 새 Board 선택 → 참조 R2의 `lastResolvedPath`를 `before`로 기록 → `v2URL`을 `directory/moved/backend`로 `FileManager.moveItem` → 새 Board에서 `selectNode(backend)`·`openSelected()`(`PastConfigurationModelTests.refreshAccessOnly`와 같은 방법) → `store.reference(R2)?.lastResolvedPath`가 옮긴 경로(`canonical` 비교) → 원본·새 Board revision 수 그대로(9, 1) → `select(project)`(원본) → 원본 현재 구성의 "backend"의 `referenceID == R2`이고 `store.reference(R2)?.lastResolvedPath`가 같은 옮긴 경로, 순번 8 스냅샷의 `recordedPath`는 그대로.
  - `@Test("시트를 연 채 다른 Board를 고르면 시트가 닫히고 뒤늦은 확정은 쓰이지 않는다")` — `beginDuplicate()` → `select(other)` → `duplication == nil`; `confirmDuplicate()` 해도 `boardCount == 2`. (Review Focus 1)
  - `@Test("새 Board를 만든 뒤 원본 Board로 돌아가면 과거 모드가 아니다")` — 만든 뒤 `select(project)` → `!isViewingPast`, `history.selection == .current`.

- [ ] **Step 2: 실패 확인** — Run: `UNIT DuplicateModelTests`. Expected: 컴파일 실패(`duplication` 등 없음).

- [ ] **Step 3: 구현** — Interfaces대로. `CreationMessage`를 재사용한다. `select(_:)`가 `loadCurrent`를 거쳐 `duplication = nil`을 하므로 확정 성공 뒤 `duplication = nil`을 먼저 하고 `select`를 부른다.

- [ ] **Step 4: 통과 확인** — Run: `UNIT DuplicateModelTests`, 이어서 `UNIT RestoreModelTests`, `UNIT PastConfigurationModelTests`, `UNIT MenuCapabilityModelTests`. Expected: 전부 통과.

- [ ] **Step 5: Commit**

```bash
git add Fianchetto/Features/BoardBrowser/BoardBrowserModel.swift FianchettoTests/Features/DuplicateModelTests.swift
git commit -m "[Duplicate] Add the new-board-from-past flow to the browser model"
```
본문: 시트는 이력 탭이 이미 읽은 목록 정보로만 만들어 파일·저장소에 접근하지 않고, 성공하면 W07처럼 새 Board를 고르며, 실패하면 입력을 유지한다는 이유를 쓴다.

---

### Task 4: 시트·메뉴·문구와 전체 검증

**Obligations:** W21-menu-order, W21-file-menu-same-sheet, W21-sheet-keyboard-accessibility, W21-menu-opens-sheet, W21-blank-name-disables-confirm

**Files:**
- Create: `Fianchetto/Features/BoardBrowser/DuplicateSheet.swift`
- Modify: `Fianchetto/Features/BoardBrowser/BoardBrowserView.swift` (`PastConfigurationBanner`의 `restore-menu`, `.sheet` 연결)
- Modify: `Fianchetto/App/BoardCommands.swift` (파일 메뉴)
- Modify: `Fianchetto/Localizable.xcstrings`, `scripts/check-terms.sh`
- Modify: `FianchettoUITests/BoardBrowserUITests.swift`

**Interfaces:**
- Consumes: Task 3 `duplication`, `canDuplicateShown`, `canConfirmDuplicate`, `canCancelDuplicate`, `beginDuplicate()`, `cancelDuplicate()`, `confirmDuplicate()`.
- Produces: 접근성 식별자 `duplicate-sheet-title`, `duplicate-name-field`, `duplicate-cancel`, `duplicate-confirm`; 메뉴 항목 `새 Board 만들기…`(띠 `restore-menu` 안, '복원…' 다음), `이 구성으로 새 Board 만들기…`(파일 메뉴, '이 구성으로 복원…' 바로 아래, 단축키 없음).

- [ ] **Step 1: UI 테스트 작성** — `BoardBrowserUITests.swift`에 추가(호스트에서 실행하지 않는다)

  ```swift
  // [W21-menu-opens-sheet] [W21-menu-order] [W21-file-menu-same-sheet] [W21-sheet-keyboard-accessibility] [W21-blank-name-disables-confirm]
  // 띠의 '이 구성으로…' › '새 Board 만들기…'와 파일 메뉴 '이 구성으로 새 Board 만들기…'가 같은 시트를 열고, 기본 이름은 전체 선택되며,
  // Esc는 취소, Return은 만들기다. 만든 뒤 새 Board가 선택된다.
  @MainActor
  func test_W21_createBoardFromPastConfiguration()
  ```
  흐름(`test_W20_restoreFromPastConfiguration`의 앞부분과 같다): Board "Plan" 만들기(⌘N) → 파일 › 'Wing 추가…'로 "Dev"(순번 2) → 보기 › '이력 보기' → `revision-row-1` 클릭 → `past-banner` 대기 → `restore-menu` 클릭 → `app.menuItems`에 '복원…'과 '새 Board 만들기…'가 둘 다 있고 `app.menuItems.allElementsBoundByIndex.map(\.title)`에서 '복원…'의 index < '새 Board 만들기…'의 index(W21-menu-order) → '새 Board 만들기…' 클릭 → `duplicate-sheet-title`의 값이 "#1 구성으로 새 Board 만들기", `duplicate-name-field`의 `value`가 "Plan 사본" → `app.typeText("Copy")` 뒤 `value`가 "Copy"(전체 선택이었다는 증거; "Plan 사본Copy"가 아니다) → 필드를 비우고(`app.typeKey("a", modifierFlags: .command)` 뒤 `.delete`) `duplicate-confirm`의 `isEnabled == false`, Return을 눌러도 시트가 남아 있다(W21-blank-name-disables-confirm) → Esc → `duplicate-sheet-title`이 없어지고 `past-banner`가 남는다 → 파일 › '이 구성으로 새 Board 만들기…' 클릭 → `duplicate-sheet-title` 다시 "#1 구성으로 새 Board 만들기", `duplicate-name-field`의 `value` "Plan 사본"(W21-file-menu-same-sheet) → Return → 시트가 없어지고 `board-row-Plan 사본`이 있으며 `isSelected`, `past-banner`가 없고 `node-row-Dev`가 없고(순번 1에는 Dev가 없다) `revision-row-1`의 라벨이 "과거 구성에서 만듦, #1, "로 시작한다. 기존 헬퍼(`UITestApp`, `text(of:)`)를 그대로 쓴다.

- [ ] **Step 2: 시트 View** — `DuplicateSheet.swift`

  `struct DuplicateSheet: View { @Bindable var model: BoardBrowserModel }`. `CreateBoardSheet`와 같은 골격(`VStack(alignment: .leading, spacing: 12)`, `.padding()`, `.frame(width: 360)`):
  - `Text(duplication.title).font(.headline).accessibilityIdentifier("duplicate-sheet-title")`
  - `Text(duplication.subtitle).font(.callout).foregroundStyle(.secondary).monospacedDigit()`
  - `TextField("Board 이름", text: Binding(get: { model.duplication?.name ?? "" }, set: { model.duplication?.name = $0 })).accessibilityIdentifier("duplicate-name-field").focused($nameFocused).onSubmit { if model.canConfirmDuplicate { confirm() } }`. `@FocusState private var nameFocused: Bool`, `.onAppear { nameFocused = true }`. 프로그램으로 초점을 주면 NSTextField가 전체를 선택한다. UI 테스트(Step 1)가 "Plan 사본" 전체 선택을 확인하고, 확인되지 않으면 `.onAppear`에서 `NSApp.keyWindow?.firstResponder`가 `NSTextView`일 때 `selectAll(nil)`을 부르는 보완을 `DuplicateSheet` 안에 둔다(AppKit은 Features 안에서 이 한 줄만, 색·파일 접근 없음).
  - `Text("새 Board는 이 구성으로 시작하고 이력은 새로 쌓입니다. 원래 Board는 바뀌지 않습니다.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)`
  - `message`가 있으면 `CreateBoardSheet`와 같은 문구·모양(`.nameRequired` → "이름을 입력하세요.", `.saveFailed` → "저장하지 못했습니다. 다시 시도하세요.", `.foregroundStyle(.red)`는 기존 시트와 같은 쓰임이라 유지).
  - `HStack { Spacer(); Button("취소", role: .cancel) { model.cancelDuplicate() }.keyboardShortcut(.cancelAction).disabled(!model.canCancelDuplicate).accessibilityIdentifier("duplicate-cancel"); Button("만들기") { confirm() }.keyboardShortcut(.defaultAction).disabled(!model.canConfirmDuplicate).accessibilityIdentifier("duplicate-confirm") }`
  - `private func confirm() { Task { await model.confirmDuplicate() } }`

- [ ] **Step 3: 띠 메뉴, 시트 연결, 파일 메뉴**

  `PastConfigurationBanner`의 `Menu("이 구성으로…")`: '복원…' 다음에 `Button("새 Board 만들기…") { model.beginDuplicate() }.disabled(!model.canDuplicateShown)`.
  `BoardBrowserView`: 복원 시트 다음에 `.sheet(isPresented: Binding(get: { model.duplication != nil }, set: { if !$0 { model.cancelDuplicate() } })) { DuplicateSheet(model: model) }`. 모델 `@Bindable` 접근은 `CreateBoardSheet`와 같은 방식.
  `BoardCommands`의 `CommandGroup(replacing: .newItem)`: `Button("이 구성으로 복원…")` 바로 아래에 `Button("이 구성으로 새 Board 만들기…") { model?.beginDuplicate() }.disabled(!isEnabled(\.canDuplicateShown))`. 단축키 없음. 기존 `Divider()` 위치는 그대로(복원 그룹 안).

- [ ] **Step 4: 문구와 용어 검사**

  `Localizable.xcstrings`에 기존 항목과 같은 형식(`comment`, `extractionState: manual`, Xcode 서식 `" : "`)으로 더한다. comment는 "새 Board 만들기 시트(W21, 0036)." 또는 "과거 구성 띠·파일 메뉴(W21).": `새 Board 만들기…`, `이 구성으로 새 Board 만들기…`, `#%lld 구성으로 새 Board 만들기`, `%@ · #%lld · %@`, `%@ 사본`, `새 Board는 이 구성으로 시작하고 이력은 새로 쌓입니다. 원래 Board는 바뀌지 않습니다.`. `만들기`·`Board 이름`·`취소`·`이름을 입력하세요.`·`저장하지 못했습니다. 다시 시도하세요.`는 이미 있으면 그대로 둔다(없는 것만 더한다).
  `scripts/check-terms.sh`의 `REQUIRED`에 `"새 Board 만들기…" "이 구성으로 새 Board 만들기…" "#%lld 구성으로 새 Board 만들기" "%@ 사본"`을 더하고 첫 줄 주석에 `W21-catalog(새 Board 만들기 시트·메뉴 문구)`를 붙인다.
  Run: `scripts/check-terms.sh && scripts/check-structure.sh && scripts/tests/check-scripts-test.sh`. Expected: 모두 OK.

- [ ] **Step 5: 빌드와 단위 테스트** — Run: `UNIT ALL`. Expected: 전부 통과, 경고 0개. UI 테스트 target은 이 명령으로 컴파일된다(실행은 건너뛴다).

- [ ] **Step 6: 디자인 세션에 알린 뒤 호스트 전체 검증(UI 제외)** — `SendMessage`로 `fianchetto-design`에 "호스트 verify 시작"을 알린다. Run: `SKIP_UI_TESTS=1 scripts/verify.sh`. Expected: 통과. TileIconSnapshotTests 라이트 2장 불일치만 실패하면 알려진 호스트 드리프트이므로 출력과 함께 보고하고 다음 단계로 간다(그 밖의 실패는 고친다).

- [ ] **Step 7: 가상 머신에서 UI 테스트 포함 전체 검증** — 디자인 세션에 "VM 사용 시작"을 알린다. Run: `scripts/vm-verify.sh`. Expected: 통과(`test_W21_createBoardFromPastConfiguration` 포함). 가상 머신을 시작할 수 없거나 스크립트가 환경 문제로 실패하면 출력 그대로 보고하고 `DONE_WITH_CONCERNS`로 끝낸다. **호스트에서 XCUITest를 실행하는 것으로 대신하지 않는다.** 끝나면 VM 사용 종료를 알린다.

- [ ] **Step 8: Commit**

```bash
git add Fianchetto/Features/BoardBrowser/DuplicateSheet.swift Fianchetto/Features/BoardBrowser/BoardBrowserView.swift \
  Fianchetto/App/BoardCommands.swift Fianchetto/Localizable.xcstrings scripts/check-terms.sh \
  FianchettoUITests/BoardBrowserUITests.swift
git commit -m "[Duplicate] Add the new-board sheet, banner menu item and File menu command"
```
본문: 띠 메뉴와 파일 메뉴(0018·0035 선례)에서 같은 시트를 열고, 기본 이름은 원본 revision의 이름이며(PR #62), 키보드 동작은 가상 머신의 UI 테스트로 확인했다(또는 확인하지 못했다)는 사실을 쓴다.

---

## 계획 이후

- `/spec-cycle:verify W21` — obligation 커버리지 확인과 `done` 기록. `superpowers:finishing-a-development-branch`보다 먼저 한다.
- PR 본문: 요약, 게이트 run `t-w21-bcfe30da`, 결정 0036, 검증(VM 결과·호스트 결과), 미검증 항목(macOS 15 실기). 병합은 디자인 세션이 VM 캡처(라이트·다크) 확인 뒤 한다. 디자인 문서 PR #62는 이 PR 뒤에 병합한다.
- macOS 15 실기 확인은 이 계획의 범위가 아니다(W27). `verify.sh` 통과를 macOS 15 통과로 보고하지 않는다.
