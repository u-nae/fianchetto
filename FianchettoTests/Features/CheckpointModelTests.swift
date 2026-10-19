import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 체크포인트 저장·조회 화면 흐름(W22): 시트 상태, 켜짐 값, 시작·취소·확정, 실패 시 입력 유지, 패널.
@MainActor
@Suite("체크포인트 저장·조회 화면 흐름 (W22)")
struct CheckpointModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let other: UUID
        let markerURL: URL
        var model: BoardBrowserModel { harness.model }
        var history: HistoryPanelModel { harness.model.history }
        var store: ProjectStore { model.openedStore!.store }

        func revisionID(_ sequence: Int) async throws -> UUID {
            try #require(try await store.revisionSummaries(projectID: project).first { $0.sequence == sequence }).id
        }

        func revisionCount() async throws -> Int { try await store.revisionSummaries(projectID: project).count }
        func checkpointCount() async throws -> Int { try await store.checkpointSummaries(projectID: project).count }
        func checkpoints(of sequence: Int) async throws -> [CheckpointSummary] {
            try await store.checkpointSummaries(projectID: project).filter { $0.sequence == sequence }
        }

        func markerContents() throws -> String { try String(contentsOf: markerURL, encoding: .utf8) }
        func openHistory() async { await model.selectInspectorTab(.history) }

        /// 시트를 열어 입력하고 확정한다.
        func save(_ title: String, note: String = "", next: String = "") async {
            await model.beginCheckpoint()
            model.checkpointDraft?.title = title
            model.checkpointDraft?.progressNote = note
            model.checkpointDraft?.nextSteps = next
            await model.confirmCheckpoint()
        }

        /// 이력 탭의 체크포인트 행을 제목으로 찾아 고른다.
        func selectCheckpoint(_ title: String) async throws {
            let summary = try #require(history.checkpoints.first { $0.title == title })
            await history.select(.checkpoint(summary.id))
        }

        /// 과거 revision에 붙은 체크포인트를 직접 심는다(시트는 현재 구성에서만 열린다).
        func plant(_ id: UUID, on sequence: Int, title: String, note: String = "", next: String = "", at: Date = date(5000)) async throws {
            let revision = try await revisionID(sequence)
            try withStore(at: harness.url) { adapter throws in
                try adapter.insert(CheckpointRecord(
                    id: id, revisionID: revision, title: title, progressNote: note, nextSteps: next, createdAt: at, attachments: []
                ))
                try adapter.save()
            }
            await model.select(project)
        }
    }

    /// 1 Board "서비스 A", 2 Bishop 폴더 backend, 3 Wing 개발, 4 웹 링크 명세(개발 아래), 5 Wing 문서, 6 명세 URL 변경. 현재 순번 6. 다른 Board "서비스 Z".
    private func opened(_ directory: URL, archived: Bool = false, unreadableCurrent: Bool = false) async throws -> Opened {
        // 서비스 시계는 seed 하네스(date(0)부터)보다 뒤에서 시작해 체크포인트 시각이 revision 기록 시각 뒤에 온다.
        let harness = BrowserHarness(directory: directory.appending(path: "browser"), serviceClock: TestClock(startingAt: date(1000)))
        let backend = try TargetFiles.folder(directory, "targets/backend")
        let marker = try TargetFiles.file(directory, "targets/backend/marker.txt", contents: "marker")
        var ids = (fixedID(1), fixedID(2))
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [backend]))
            let development = try #require(try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board).committed)
                .snapshot.node(named: "개발")!.id
            let spec = try #require(try await seed.service.apply(
                .addWebLink(name: "명세", url: "https://example.com/spec", parentID: development, position: nil), to: board
            ).committed).snapshot.node(named: "명세")!.id
            _ = try await seed.service.apply(.addGroup(name: "문서", parentID: nil, position: nil), to: board)
            _ = try await seed.service.apply(.changeURL(spec, "https://example.com/spec-v2"), to: board)
            if archived { try await seed.store.setArchived(board, at: date(100)) }
            let other = try await makeBoard(seed, "서비스 Z")
            ids = (board, other)
        }
        if unreadableCurrent {
            try withStore(at: harness.url) { adapter throws in
                let models = try adapter.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>())
                try #require(models.first { $0.sequence == 6 && $0.projectID == ids.0 }).snapshotData = Data("{".utf8)
                try adapter.save()
            }
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, project: ids.0, other: ids.1, markerURL: marker)
    }

    nonisolated static let c1 = fixedID(7101)
    nonisolated static let c2 = fixedID(7102)

    // MARK: 진입

    @Test("[W22-file-menu-opens-sheet] 시작하면 현재 revision을 고정한 빈 시트가 열리고 아무것도 저장하지 않는다")
    func beginOpensSheet() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.beginCheckpoint()
            let draft = try #require(o.model.checkpointDraft)
            #expect(draft.revisionID == (try await o.revisionID(6)))
            #expect(draft.sequence == 6)
            #expect(draft.subtitle.hasPrefix("현재 구성 · #6 · "))
            #expect(draft.subtitle.hasSuffix(" 기록"))
            #expect(draft.title == "" && draft.progressNote == "" && draft.nextSteps == "")
            #expect(draft.message == nil)
            #expect(!o.model.canConfirmCheckpoint)
            #expect(o.model.canCancelCheckpoint)
            #expect(try await o.revisionCount() == 6)
            #expect(try await o.checkpointCount() == 0)
        }
    }

    @Test("[W22-toolbar-opens-sheet] 툴바와 파일 메뉴는 같은 시작 동작을 쓰고 열린 동안 다시 열지 않는다")
    func beginOnce() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(o.model.canSaveCheckpoint)
            await o.model.beginCheckpoint()
            let first = o.model.checkpointDraft
            #expect(!o.model.canSaveCheckpoint)
            o.model.checkpointDraft?.title = "유지"
            await o.model.beginCheckpoint()
            #expect(o.model.checkpointDraft?.title == "유지")
            #expect(o.model.checkpointDraft?.revisionID == first?.revisionID)
        }
    }

    enum Situation: CaseIterable { case current, past, comparing, archived, noBoard, unreadableCurrent, createSheetOpen, checkpointSheetOpen }

    @Test("[W22-entry-enablement] 저장 명령은 편집할 수 있는 현재 구성을 볼 때만 켜진다", arguments: Situation.allCases)
    func enablement(_ situation: Situation) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let model: BoardBrowserModel
            if situation == .noBoard {
                let harness = BrowserHarness(directory: directory.appending(path: "empty"))
                await harness.model.start()
                model = harness.model
            } else {
                let o = try await opened(directory, archived: situation == .archived, unreadableCurrent: situation == .unreadableCurrent)
                model = o.model
                switch situation {
                case .past: await o.openHistory(); await o.history.select(.revision(try await o.revisionID(4)))
                case .comparing:
                    await o.openHistory(); await o.history.select(.revision(try await o.revisionID(4)))
                    await o.model.compareWithCurrent()
                    #expect(o.model.isComparing)
                case .createSheetOpen: o.model.beginCreate(); #expect(o.model.creation != nil)
                case .checkpointSheetOpen: await o.model.beginCheckpoint(); #expect(o.model.checkpointDraft != nil)
                case .unreadableCurrent: #expect(o.model.current == .unreadable)
                default: break
                }
            }
            let expected = situation == .current
            #expect(model.canSaveCheckpoint == expected)
            let before = model.checkpointDraft
            await model.beginCheckpoint()
            if expected {
                #expect(model.checkpointDraft != nil)
            } else {
                #expect(model.checkpointDraft == before)
            }
        }
    }

    @Test("[W22-open-read-failure] 현재 revision 정보를 읽지 못하면 시트를 열지 않고 안내한다")
    func readFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            // 저장소에서 Board 레코드를 지워 현재 revision 정보를 읽지 못하게 한다(테스트 fixture 조작).
            try withStore(at: o.harness.url) { adapter throws in
                let project = o.project
                let model = try #require(try adapter.context.fetch(FetchDescriptor<SchemaV1.ProjectModel>(predicate: #Predicate { $0.id == project })).first)
                adapter.context.delete(model)
                try adapter.save()
            }
            await o.model.beginCheckpoint()
            #expect(o.model.checkpointDraft == nil)
            let notice = try #require(o.model.linkNotice)
            #expect(notice.kind == .readFailed)
            #expect(notice.action == .checkpoint)
            #expect(o.model.noticeTitle(notice) == "체크포인트 저장")
            #expect(o.model.noticeText(notice) == "기록을 불러오지 못했습니다")
            #expect(try await o.revisionCount() == 6)
            #expect(try await o.checkpointCount() == 0)
        }
    }

    // MARK: 시트

    @Test("[W22-blank-title-disables-save] 공백·줄바꿈뿐인 제목이면 확정이 꺼지고 호출해도 저장하지 않는다", arguments: ["   ", "\n\t", ""])
    func blankTitle(_ title: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.beginCheckpoint()
            o.model.checkpointDraft?.title = title
            o.model.checkpointDraft?.progressNote = "메모"
            #expect(!o.model.canConfirmCheckpoint)
            await o.model.confirmCheckpoint()
            #expect(try await o.checkpointCount() == 0)
            #expect(o.model.checkpointDraft != nil)
            #expect(o.model.checkpointDraft?.message == nil)
        }
    }

    @Test("[W22-no-revision-while-typing] 입력 중에는 revision·현재 revision이 그대로이고 체크포인트도 없다", .tags(.A10))
    func noRevisionWhileTyping() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.beginCheckpoint()
            o.model.checkpointDraft?.title = "작성 중"
            o.model.checkpointDraft?.progressNote = "아직 저장 전"
            #expect(try await o.revisionCount() == 6)
            #expect(try await o.store.project(o.project)?.currentRevisionID == (try await o.revisionID(6)))
            #expect(try await o.checkpointCount() == 0)
        }
    }

    @Test("[W22-cancel-discards-input] 취소하면 아무것도 저장하지 않고 다시 열면 비어 있다")
    func cancelDiscards() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.beginCheckpoint()
            o.model.checkpointDraft?.title = "버릴 제목"
            o.model.checkpointDraft?.progressNote = "버릴 메모"
            o.model.cancelCheckpoint()
            #expect(o.model.checkpointDraft == nil)
            #expect(try await o.checkpointCount() == 0)
            #expect(try await o.revisionCount() == 6)
            #expect(!o.model.isViewingPast)
            await o.model.beginCheckpoint()
            let draft = try #require(o.model.checkpointDraft)
            #expect(draft.title == "" && draft.progressNote == "" && draft.nextSteps == "")
        }
    }

    @Test("[W22-sheet-keyboard-accessibility] 시트는 부제·세 입력·실패 문구 상태를 가지고 열린 동안 재진입하지 않는다")
    func sheetState() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.beginCheckpoint()
            o.model.checkpointDraft?.title = "키보드"
            let draft = try #require(o.model.checkpointDraft)
            #expect(draft.subtitle.hasPrefix("현재 구성 · #6 · "))
            #expect(draft.title == "키보드" && draft.progressNote == "" && draft.nextSteps == "")
            #expect(draft.message == nil)
            #expect(o.model.canConfirmCheckpoint && o.model.canCancelCheckpoint)
            #expect(!o.model.canSaveCheckpoint)
        }
    }

    @Test("[W22-sheet-blocks-editing] 시트가 열린 동안 편집·Board 상태 변경·다시 선택은 꺼지고 조회 명령은 그대로이며 닫으면 돌아온다")
    func blocksEditing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.selectNode(try #require(o.model.loadedSnapshot?.node(named: "backend")).id)
            let edits: @MainActor () -> [Bool] = {
                [o.model.canAddToBoard, o.model.canRenameSelectedNode, o.model.canMoveSelected, o.model.canRemoveSelected,
                 o.model.canRenameSelectedBoard, o.model.canArchiveSelected, o.model.canCreateBoard, o.model.canReselectSelected,
                 o.model.canReplaceSelectedTarget, o.model.canAcceptDrop(on: nil),
                 o.model.canAcceptNodeDrop(o.model.loadedSnapshot!.node(named: "backend")!.id, on: nil)]
            }
            let views: @MainActor () -> [Bool] = {
                [o.model.canRefreshStatuses, o.model.canOpenSelected, o.model.canRevealSelected, o.model.canShowHistory]
            }
            let editsBefore = edits(), viewsBefore = views()
            #expect(editsBefore.allSatisfy { $0 })
            await o.model.beginCheckpoint()
            #expect(edits().allSatisfy { !$0 })
            #expect(!o.model.canRestoreShown && !o.model.canDuplicateShown)
            #expect(views() == viewsBefore)
            o.model.beginCreate()
            #expect(o.model.creation == nil)
            o.model.beginAddGroup()
            #expect(o.model.nodeForm == nil)
            o.model.beginRenameNode()
            #expect(o.model.nodeForm == nil)
            o.model.beginRemove()
            #expect(o.model.removal == nil)
            await o.model.archiveSelected()
            #expect(o.model.archivedNames.isEmpty)
            o.model.cancelCheckpoint()
            #expect(edits() == editsBefore)
            #expect(views() == viewsBefore)
        }
    }

    @Test("[W22-single-save-while-saving] 확정을 연달아 두 번 요청해도 체크포인트는 하나만 생긴다")
    func singleSave() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.beginCheckpoint()
            o.model.checkpointDraft?.title = "한 번만"
            async let a: Void = o.model.confirmCheckpoint()
            async let b: Void = o.model.confirmCheckpoint()
            _ = await (a, b)
            #expect(try await o.checkpointCount() == 1)
            #expect(o.model.checkpointDraft == nil)
        }
    }

    // MARK: 저장

    @Test("[W22-save-attaches-to-fixed-revision] 확정하면 고정한 revision에 체크포인트가 붙고 revision은 늘지 않으며 화면은 현재 구성에 머문다", .tags(.A10))
    func saveAttaches() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.openHistory()
            await o.save("인증 1차", note: "로그인 완료", next: "토큰 갱신")
            #expect(o.model.checkpointDraft == nil)
            let saved = try #require(try await o.checkpoints(of: 6).first)
            let record = try #require(try await o.store.checkpoint(saved.id))
            #expect(record.title == "인증 1차" && record.progressNote == "로그인 완료" && record.nextSteps == "토큰 갱신")
            let sixth = try #require(try await o.store.revisionSummary(try await o.revisionID(6)))
            #expect(record.createdAt > sixth.recordedAt)
            #expect(o.harness.serviceClock.now() == record.createdAt.addingTimeInterval(1))
            #expect(try await o.revisionCount() == 6)
            #expect(try await o.store.project(o.project)?.currentRevisionID == sixth.id)
            #expect(!o.model.isViewingPast)
            #expect(o.model.checkpointPanel == nil)
            #expect(o.model.canAddToBoard)
            #expect(o.history.selection == .current)
            if case let .checkpoint(summary)? = o.history.entries.first {
                #expect(summary.title == "인증 1차")
            } else {
                Issue.record("첫 행이 체크포인트가 아니다: \(o.history.entries.first.map { "\($0)" } ?? "없음")")
            }
        }
    }

    @Test("[W22-history-updates-after-save] 이력 탭이 열린 채 저장하면 행이 더해지고 선택은 현재 구성에 남는다")
    func historyUpdatesAfterSave() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.openHistory()
            await o.history.select(.current)
            #expect(o.history.entries.count == 6)
            await o.save("열린 채 저장")
            #expect(o.history.entries.count == 7)
            if case let .checkpoint(summary)? = o.history.entries.first { #expect(summary.title == "열린 채 저장") } else { Issue.record("행이 없다") }
            #expect(o.history.selection == .current)
            #expect(!o.model.isViewingPast)
        }
    }

    @Test("[W22-save-failure-keeps-input] 저장이 실패하면 체크포인트가 생기지 않고 입력을 유지한 채 알리며 다시 시도할 수 있다")
    func saveFailureKeepsInput() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.fault.failNext()
            await o.save("실패 뒤", note: "메모 유지", next: "할 일 유지")
            #expect(try await o.checkpointCount() == 0)
            #expect(try await o.revisionCount() == 6)
            let draft = try #require(o.model.checkpointDraft)
            #expect(draft.title == "실패 뒤" && draft.progressNote == "메모 유지" && draft.nextSteps == "할 일 유지")
            #expect(draft.message == .saveFailed)
            #expect(!draft.isSaving)
            #expect(o.model.canConfirmCheckpoint)
            await o.model.confirmCheckpoint()
            #expect(try await o.checkpointCount() == 1)
            #expect(o.model.checkpointDraft == nil)
        }
    }

    @Test("[W22-save-no-file-access] 저장은 파일 시스템 접근·접근 정보 해석·연결 대상 열기를 하지 않는다")
    func noFileAccess() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try o.markerContents()
            let resolutions = o.harness.bookmarks.scopedResolutions.count
            await o.save("파일 접근 없음")
            #expect(try await o.checkpointCount() == 1)
            #expect(try o.markerContents() == before)
            #expect(o.harness.bookmarks.scopedResolutions.count == resolutions)
            #expect(o.harness.launcher.opened.isEmpty && o.harness.launcher.revealed.isEmpty)
        }
    }

    // MARK: 조회

    @Test("[W22-select-shows-past-and-panel] 체크포인트 행을 고르면 과거 구성·띠·패널이 보이고 고른 항목 카드는 유지된다", .tags(.A10))
    func selectShowsPanel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.plant(Self.c1, on: 4, title: "명세 확정", note: "명세 링크 정리함", next: "문서 Wing 만들기")
            await o.openHistory()
            try await o.selectCheckpoint("명세 확정")
            #expect(o.model.isViewingPast)
            #expect(o.model.pastBannerDetail?.hasPrefix("#4 · ") == true)
            #expect(!o.model.canAddToBoard)
            #expect(o.model.checkpointPanel == BoardBrowserModel.CheckpointPanel(
                title: "명세 확정", savedText: o.history.savedText(date(5000)), progressNote: "명세 링크 정리함", nextSteps: "문서 Wing 만들기", isCollapsed: false
            ))
            #expect(o.history.selection == .checkpoint(Self.c1))
            await o.model.selectNode(try #require(o.model.shownSnapshot?.node(named: "명세")).id)
            #expect(o.model.pastItemCard?.url == "https://example.com/spec")
            #expect(try await o.revisionCount() == 6)
        }
    }

    @Test("[W22-select-current-revision-checkpoint] 현재 revision에 붙은 체크포인트를 골라도 과거 모드와 패널이 보이고 저장 명령은 꺼진다", .tags(.A10))
    func selectCurrentRevisionCheckpoint() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.save("지금 구성")
            await o.openHistory()
            try await o.selectCheckpoint("지금 구성")
            #expect(o.model.isViewingPast)
            #expect(o.model.pastBannerDetail?.hasPrefix("#6 · ") == true)
            #expect(o.model.checkpointPanel?.title == "지금 구성")
            #expect(o.history.selection != .current)
            #expect(!o.model.canSaveCheckpoint)
            #expect(!o.model.canAddToBoard)
        }
    }

    @Test("[W22-panel-omits-empty-columns] 패널은 공백뿐인 열을 빼고 둘 다 비면 제목만 둔다")
    func panelOmitsEmptyColumns() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.save("메모만", note: "진행 중", next: "")
            await o.save("제목만", note: "", next: "   ")
            await o.openHistory()
            try await o.selectCheckpoint("메모만")
            #expect(o.model.checkpointPanel?.progressNote == "진행 중")
            #expect(o.model.checkpointPanel?.nextSteps == nil)
            try await o.selectCheckpoint("제목만")
            #expect(o.model.checkpointPanel?.title == "제목만")
            #expect(o.model.checkpointPanel?.progressNote == nil)
            #expect(o.model.checkpointPanel?.nextSteps == nil)
        }
    }

    @Test("[W22-panel-collapse] 접기는 화면 상태이고 다른 체크포인트를 고르면 펴진다")
    func panelCollapse() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.save("첫째", note: "첫째 메모")
            await o.save("둘째", note: "둘째 메모")
            await o.openHistory()
            try await o.selectCheckpoint("첫째")
            #expect(o.model.checkpointToggleHelp == "체크포인트 접기")
            o.model.toggleCheckpointPanel()
            #expect(o.model.checkpointPanel?.isCollapsed == true)
            #expect(o.model.checkpointToggleHelp == "체크포인트 펴기")
            #expect(try await o.revisionCount() == 6)
            #expect(try await o.checkpointCount() == 2)
            try await o.selectCheckpoint("둘째")
            #expect(o.model.checkpointPanel?.isCollapsed == false)
            #expect(o.model.checkpointPanel?.progressNote == "둘째 메모")
            #expect(o.model.checkpointToggleHelp == "체크포인트 접기")
        }
    }

    @Test("[W22-compare-with-current-hides-panel] 비교 중에는 패널이 없고 닫으면 돌아오며 비교 중 다른 체크포인트를 고르면 비교가 닫힌다")
    func compareHidesPanel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.plant(Self.c1, on: 4, title: "명세 확정")
            try await o.plant(Self.c2, on: 5, title: "문서 추가", at: date(5100))
            await o.openHistory()
            try await o.selectCheckpoint("명세 확정")
            await o.model.compareWithCurrent()
            #expect(o.model.isComparing)
            #expect(o.model.checkpointPanel == nil)
            o.model.closeComparison()
            #expect(o.model.checkpointPanel?.title == "명세 확정")
            #expect(o.history.selection == .checkpoint(Self.c1))
            await o.model.compareWithCurrent()
            try await o.selectCheckpoint("문서 추가")
            #expect(!o.model.isComparing)
            #expect(o.model.pastBannerDetail?.hasPrefix("#5 · ") == true)
            #expect(o.model.checkpointPanel?.title == "문서 추가")
        }
    }

    @Test("[W22-compare-record-menu] 체크포인트 행의 '이 기록과 비교'는 그 revision 행과 같다")
    func compareRecordMenu() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.plant(Self.c1, on: 4, title: "명세 확정")
            await o.openHistory()
            let fourth = try await o.revisionID(4), fifth = try await o.revisionID(5)
            #expect(o.model.canCompareRecord(.checkpoint(Self.c1)))
            await o.model.compareRecord(.checkpoint(Self.c1))
            #expect(o.model.isComparing)
            #expect(o.model.comparison.before == .revision(fourth))
            #expect(o.model.comparison.after == .current)
            o.model.closeComparison()
            await o.history.select(.revision(fourth))
            #expect(!o.model.canCompareRecord(.checkpoint(Self.c1)))
            try await o.selectCheckpoint("명세 확정")
            #expect(!o.model.canCompareRecord(.revision(fourth)))
            #expect(o.model.canCompareRecord(.revision(fifth)))
            #expect(!o.model.canCompareRecord(.checkpoint(Self.c1)))
        }
    }

    @Test("[W22-restore-is-separate] 체크포인트 보기에서 복원하면 새 revision이 생기고 체크포인트는 원래 revision에 남는다")
    func restoreIsSeparate() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.plant(Self.c1, on: 4, title: "명세 확정")
            await o.openHistory()
            try await o.selectCheckpoint("명세 확정")
            let fourth = try await o.revisionID(4)
            #expect(o.model.canRestoreShown)
            o.model.beginRestore()
            await o.model.confirmRestore()
            #expect(try await o.revisionCount() == 7)
            let seventh = try #require(try await o.store.revisionSummaries(projectID: o.project).first { $0.sequence == 7 })
            #expect(seventh.cause == .restored(from: fourth))
            #expect(try await o.checkpoints(of: 4).count == 1)
            #expect(try await o.checkpoints(of: 7).isEmpty)
            #expect(!o.model.isViewingPast)
            #expect(o.model.checkpointPanel == nil)
        }
    }

    @Test("[W22-icon-view-same-panel] 아이콘 보기에서도 체크포인트를 고르면 같은 띠와 패널이다")
    func iconViewSamePanel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.plant(Self.c1, on: 4, title: "명세 확정")
            o.model.showIcons()
            await o.openHistory()
            try await o.selectCheckpoint("명세 확정")
            #expect(o.model.viewMode == .icons)
            #expect(o.model.isViewingPast)
            #expect(o.model.checkpointPanel?.title == "명세 확정")
            #expect(!o.model.canAddToBoard)
        }
    }

    enum Return: CaseIterable { case banner, currentRow }

    @Test("[W22-return-to-current] 띠와 현재 구성 행으로 돌아가면 패널이 사라진다", arguments: Return.allCases)
    func returnToCurrent(_ way: Return) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.plant(Self.c1, on: 4, title: "명세 확정")
            await o.openHistory()
            try await o.selectCheckpoint("명세 확정")
            #expect(o.model.checkpointPanel != nil)
            switch way {
            case .banner: await o.model.returnToCurrent()
            case .currentRow: await o.history.select(.current)
            }
            #expect(o.model.checkpointPanel == nil)
            #expect(!o.model.isViewingPast)
        }
    }

    @Test("시트를 연 채 다른 Board를 고르면 시트가 닫히고 뒤늦은 저장은 쓰이지 않는다")
    func boardSwitchClosesSheet() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.beginCheckpoint()
            o.model.checkpointDraft?.title = "늦은 저장"
            await o.model.select(o.other)
            #expect(o.model.checkpointDraft == nil)
            await o.model.confirmCheckpoint()
            #expect(try await o.checkpointCount() == 0)
            #expect(try await o.store.checkpointSummaries(projectID: o.other).isEmpty)
        }
    }

    @Test("체크포인트를 고른 채 이력 탭을 닫아도 띠와 패널이 이어진다")
    func closingTabKeepsPanel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.plant(Self.c1, on: 4, title: "명세 확정")
            await o.openHistory()
            try await o.selectCheckpoint("명세 확정")
            await o.model.selectInspectorTab(.item)
            #expect(o.model.isViewingPast)
            #expect(o.model.checkpointPanel?.title == "명세 확정")
        }
    }
}
