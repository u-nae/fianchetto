import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 과거 구성에서 새 Board를 만드는 화면 흐름(W21): 시트 상태, 켜짐 판단 값, 시작·취소·확정, 실패 시 입력 유지.
@MainActor
@Suite("과거 구성에서 새 Board 만들기 화면 흐름 (W21)")
struct DuplicateModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let directory: URL
        let project: UUID
        let other: UUID
        let legacyURL: URL
        let v2URL: URL
        let notesURL: URL
        var model: BoardBrowserModel { harness.model }
        var history: HistoryPanelModel { harness.model.history }
        var store: ProjectStore { model.openedStore!.store }

        func summary(_ sequence: Int, of board: UUID? = nil) async throws -> RevisionSummary {
            try #require(try await store.revisionSummaries(projectID: board ?? project).first { $0.sequence == sequence })
        }

        func revisionID(_ sequence: Int) async throws -> UUID { try await summary(sequence).id }

        func revisionCount(of board: UUID? = nil) async throws -> Int {
            try await store.revisionSummaries(projectID: board ?? project).count
        }

        var boardCount: Int { model.activeNames.count + model.archivedNames.count }

        func newBoard() -> ProjectListing? { model.board(named: "서비스 알파 사본") }

        /// 이력 탭을 열고 그 순번의 구성을 본다.
        func viewPast(_ sequence: Int) async throws {
            await model.selectInspectorTab(.history)
            await history.select(.revision(try await revisionID(sequence)))
        }

        /// 두 대상 폴더와 notes.md의 파일 이름과 내용.
        func targetFiles() throws -> [String: String] {
            var result: [String: String] = [:]
            for folder in [legacyURL, v2URL] {
                for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() {
                    result[folder.appending(path: name).path] = try String(contentsOf: folder.appending(path: name), encoding: .utf8)
                }
            }
            result[notesURL.path] = try String(contentsOf: notesURL, encoding: .utf8)
            return result
        }
    }

    /// 1 Board 만들기("서비스 알파"), 2 Bishop backend(legacy) 추가, 3 대상 교체(v2), 4 Wing "문서", 5 Wing "개발",
    /// 6 "개발" 안 웹 링크 "명세", 7 "개발" 안 Bishop notes.md, 8 notes.md 아이콘 document, 9 이름 "서비스 A". 다른 Board "서비스 B".
    private func opened(_ directory: URL, archived: Bool = false) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let legacy = try TargetFiles.folder(directory, "targets/legacy/backend")
        let v2 = try TargetFiles.folder(directory, "targets/v2/backend")
        _ = try TargetFiles.file(directory, "targets/legacy/backend/marker.txt", contents: "legacy marker")
        _ = try TargetFiles.file(directory, "targets/v2/backend/marker.txt", contents: "v2 marker")
        let notes = try TargetFiles.file(directory, "targets/docs/notes.md", contents: "notes marker")
        var ids = (fixedID(1), fixedID(2))
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 알파")
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [legacy]))
            let backend = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "backend")).id
            let replacement = TargetReplacementService(bookmarks: BookmarkAdapter(system: seed.bookmarks), configuration: seed.service)
            let preview = try await replacement.preview(projectID: board, nodeID: backend, newURL: v2).get()
            _ = try await replacement.confirm(preview)
            _ = try await seed.service.apply(.addGroup(name: "문서", parentID: nil, position: nil), to: board)
            let development = try #require(try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board).committed)
                .snapshot.node(named: "개발")!.id
            _ = try await seed.service.apply(.addWebLink(name: "명세", url: "https://example.com/spec", parentID: development, position: nil), to: board)
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: development, position: nil, urls: [notes]))
            let notesID = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "notes.md")).id
            _ = try await seed.service.apply(.changePurpose(notesID, "document"), to: board)
            _ = try await seed.service.apply(.renameProject("서비스 A"), to: board)
            let other = try await makeBoard(seed, "서비스 B")
            if archived { try await seed.store.setArchived(board, at: date(100)) }
            ids = (board, other)
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, directory: directory, project: ids.0, other: ids.1, legacyURL: legacy, v2URL: v2, notesURL: notes)
    }

    private func canonical(_ path: String?) -> String? {
        path.map { URL(filePath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
    }

    /// ID를 뺀 구조: 종류·이름·부모 이름·순서·URL·아이콘·참조·당시 경로.
    private func structure(_ snapshot: ConfigurationSnapshot) -> [[String]] {
        let names = Dictionary(snapshot.nodes.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        return snapshot.nodes.map { node in
            [node.kind.rawValue, node.displayName, node.parentID.flatMap { names[$0] } ?? "", String(node.sortIndex),
             node.url ?? "", node.purpose ?? "", node.referenceID?.uuidString ?? "", node.recordedPath ?? ""]
        }.sorted { ($0[2], $0[3]) < ($1[2], $1[3]) }
    }

    // MARK: 시트 열기

    @Test("[W21-menu-opens-sheet] 과거 구성에서 만들기를 시작하면 이름 시트가 열리고 아무것도 저장하지 않는다")
    func opensSheet() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            #expect(o.model.canDuplicateShown)
            o.model.beginDuplicate()
            let sheet = try #require(o.model.duplication)
            #expect(sheet.title == "#8 구성으로 새 Board 만들기")
            #expect(sheet.subtitle.hasPrefix("서비스 알파 · #8 · "))
            #expect(sheet.name == "서비스 알파 사본")
            #expect(sheet.message == nil)
            #expect(!sheet.isSaving)
            #expect(sheet.sourceBoardID == o.project)
            #expect(sheet.revisionID == (try await o.revisionID(8)))
            #expect(o.model.canConfirmDuplicate)
            #expect(o.model.canCancelDuplicate)
            #expect(o.boardCount == 2)
            #expect(try await o.revisionCount() == 9)
        }
    }

    @Test("[W21-archived-menu-enabled] 보관된 Board의 과거 구성에서 만들기는 켜지고 복원은 꺼진다")
    func archivedEnablesDuplicateOnly() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            try await o.viewPast(8)
            #expect(o.model.canDuplicateShown)
            #expect(!o.model.canRestoreShown)
            o.model.beginDuplicate()
            #expect(o.model.duplication != nil)
        }
    }

    enum Situation: CaseIterable, CustomTestStringConvertible {
        case current, past, comparing, archivedPast, duplicateSheetOpen, restoreSheetOpen
        var testDescription: String {
            switch self {
            case .current: "현재 구성"
            case .past: "과거 구성"
            case .comparing: "비교 중"
            case .archivedPast: "보관된 Board의 과거 구성"
            case .duplicateSheetOpen: "만들기 시트 열림"
            case .restoreSheetOpen: "복원 시트 열림"
            }
        }
    }

    @Test("[W21-file-menu-enablement] 만들기 명령은 과거 구성을 볼 때만 켜지고 시트가 열려 있으면 꺼진다", arguments: Situation.allCases)
    func enablement(_ situation: Situation) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: situation == .archivedPast)
            switch situation {
            case .current: break
            case .past, .archivedPast: try await o.viewPast(8)
            case .comparing:
                try await o.viewPast(8)
                await o.model.compareWithCurrent()
                #expect(o.model.isComparing)
            case .duplicateSheetOpen:
                try await o.viewPast(8)
                o.model.beginDuplicate()
                #expect(o.model.duplication != nil)
                #expect(!o.model.canRestoreShown)
            case .restoreSheetOpen:
                try await o.viewPast(8)
                o.model.beginRestore()
                #expect(o.model.restorePreview != nil)
            }
            let expected = situation == .past || situation == .archivedPast
            #expect(o.model.canDuplicateShown == expected)
            let before = o.model.duplication
            o.model.beginDuplicate()
            if expected {
                #expect(o.model.duplication != nil)
            } else {
                #expect(o.model.duplication == before)
            }
        }
    }

    @Test("[W21-blank-name-disables-confirm] 공백뿐인 이름이면 확정이 꺼지고 호출해도 만들지 않는다")
    func blankNameDisablesConfirm() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            o.model.duplication?.name = "   "
            #expect(!o.model.canConfirmDuplicate)
            await o.model.confirmDuplicate()
            #expect(o.boardCount == 2)
            #expect(o.model.duplication != nil)
            #expect(o.model.duplication?.message == nil)
        }
    }

    @Test("[W21-cancel-keeps-past-view] 취소하면 아무것도 저장하지 않고 과거 구성 보기가 이어진다")
    func cancelKeepsPast() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            o.model.duplication?.name = "버릴 이름"
            o.model.cancelDuplicate()
            #expect(o.model.duplication == nil)
            #expect(o.model.isViewingPast)
            #expect(o.history.selectedRevisionID == (try await o.revisionID(8)))
            #expect(o.model.selectedBoardID == o.project)
            #expect(o.boardCount == 2)
            #expect(try await o.revisionCount() == 9)
        }
    }

    @Test("[W21-sheet-keyboard-accessibility] 시트는 제목·부제·이름·취소 가능 상태를 가진다")
    func sheetTexts() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            let sheet = try #require(o.model.duplication)
            let recordedAt = try await o.summary(8).recordedAt
            #expect(sheet.title == "#8 구성으로 새 Board 만들기")
            #expect(sheet.subtitle == "서비스 알파 · #8 · \(o.history.dateTimeText(recordedAt))")
            #expect(sheet.name == "서비스 알파 사본")
            #expect(o.model.canCancelDuplicate)
        }
    }

    @Test("[W21-single-confirm-while-saving] 확정을 연달아 두 번 요청해도 Board는 하나만 생긴다")
    func singleConfirm() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            async let a: Void = o.model.confirmDuplicate()
            async let b: Void = o.model.confirmDuplicate()
            _ = await (a, b)
            #expect(o.boardCount == 3)
            #expect(o.model.activeNames.filter { $0 == "서비스 알파 사본" }.count == 1)
            #expect(o.model.duplication == nil)
        }
    }

    // MARK: 확정

    @Test("[W21-confirm-creates-board] 확정하면 새 Board가 생겨 선택되고 현재 구성을 보인다", .tags(.A09))
    func confirmCreatesBoard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            let source = try #require(o.model.shownSnapshot)
            let sourceRecordedAt = try await o.summary(8).recordedAt
            o.model.beginDuplicate()
            o.model.duplication?.name = "서비스 C"
            await o.model.confirmDuplicate()
            #expect(o.model.duplication == nil)
            // 목록 순서는 만든 시각 기준이고 테스트 시계는 seed와 독립이라 집합으로 비교한다.
            #expect(Set(o.model.activeNames) == ["서비스 A", "서비스 B", "서비스 C"])
            #expect(o.model.archivedNames.isEmpty)
            let created = try #require(o.model.board(named: "서비스 C"))
            #expect(o.model.selectedBoardID == created.id)
            #expect(!o.model.isViewingPast)
            #expect(!o.model.isComparing)
            #expect(o.history.selection == .current)
            let loaded = try #require(o.model.loadedSnapshot)
            #expect(loaded.projectName == "서비스 C")
            #expect(structure(loaded) == structure(source))
            #expect(Set(loaded.nodes.map(\.id)).isDisjoint(with: source.nodes.map(\.id)))
            #expect(try await o.revisionCount(of: created.id) == 1)
            let first = try await o.summary(1, of: created.id)
            #expect(first.cause == .duplicated)
            #expect(first.recordedAt != sourceRecordedAt)
            #expect(try await o.revisionCount() == 9)
            #expect(o.model.inspectorTab == .history)
            let row = try #require(o.history.rows.first)
            #expect(o.history.causeText(row) == "과거 구성에서 만듦")
        }
    }

    @Test("[W21-archived-source-allowed] 보관된 Board의 과거 구성으로 만든 새 Board는 보관되지 않은 채 선택된다")
    func archivedSourceAllowed() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            await o.model.confirmDuplicate()
            #expect(o.model.activeNames.contains("서비스 알파 사본"))
            #expect(o.model.archivedNames == ["서비스 A"])
            #expect(o.model.selectedBoardID == o.newBoard()?.id)
            #expect(try await o.revisionCount() == 9)
        }
    }

    @Test("[W21-copies-unreachable-items] 접근할 수 없는 항목도 그대로 복사하고 만들기 동안 해석하지 않으며 상태는 고를 때 확인한다")
    func copiesUnreachableItems() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.bookmarks.failResolution(with: NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError))
            try await o.viewPast(8)
            let sourceReference = try #require(o.model.shownSnapshot?.node(named: "backend")?.referenceID)
            o.model.beginDuplicate()
            let resolutions = o.harness.bookmarks.scopedResolutions.count
            await o.model.confirmDuplicate()
            #expect(o.harness.bookmarks.scopedResolutions.count == resolutions)
            #expect(o.model.selectedBoardID == o.newBoard()?.id)
            let backend = try #require(o.model.loadedSnapshot?.node(named: "backend"))
            #expect(backend.referenceID == sourceReference)
            await o.model.selectNode(backend.id)
            #expect(o.model.displayedStatus(of: backend.id) == .missing)
            #expect(o.model.canReselectSelected)
            #expect(o.model.canRefreshStatuses)
        }
    }

    @Test("[W21-no-disk-side-effects] 만들기는 연결 대상 원본을 읽거나 바꾸지 않는다")
    func noDiskSideEffects() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try o.targetFiles()
            #expect(before.count == 3)
            try await o.viewPast(8)
            let resolutions = o.harness.bookmarks.scopedResolutions.count
            o.model.beginDuplicate()
            await o.model.confirmDuplicate()
            #expect(o.boardCount == 3)
            #expect(try o.targetFiles() == before)
            #expect(o.harness.launcher.opened.isEmpty)
            #expect(o.harness.launcher.revealed.isEmpty)
            #expect(o.harness.actions.revealed.isEmpty)
            #expect(o.harness.bookmarks.scopedResolutions.count == resolutions)
        }
    }

    @Test("[W21-save-failure-keeps-input] 저장이 실패하면 새 Board가 생기지 않고 시트는 입력을 유지한 채 알리며 다시 시도할 수 있다")
    func saveFailureKeepsInput() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            o.model.duplication?.name = "서비스 C"
            o.harness.fault.failNext()
            await o.model.confirmDuplicate()
            #expect(o.boardCount == 2)
            let sheet = try #require(o.model.duplication)
            #expect(sheet.name == "서비스 C")
            #expect(sheet.message == .saveFailed)
            #expect(!sheet.isSaving)
            #expect(o.model.canConfirmDuplicate)
            #expect(o.model.isViewingPast)
            #expect(o.history.selectedRevisionID == (try await o.revisionID(8)))
            await o.model.confirmDuplicate()
            #expect(o.model.activeNames.contains("서비스 C"))
            #expect(o.model.duplication == nil)
        }
    }

    @Test("[W21-shared-access-info] 한쪽 Board에서 같은 대상의 접근 정보를 갱신하면 같은 참조를 쓰는 다른 Board에서도 보인다")
    func sharedAccessInfo() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            await o.model.confirmDuplicate()
            let created = try #require(o.newBoard())
            #expect(o.model.selectedBoardID == created.id)
            let backend = try #require(o.model.loadedSnapshot?.node(named: "backend"))
            let referenceID = try #require(backend.referenceID)
            let original = try #require(try await o.store.reference(referenceID))
            let moved = directory.appending(path: "moved/backend")
            try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: o.v2URL, to: moved)

            await o.model.selectNode(backend.id)
            await o.model.openSelected()
            let updated = try #require(try await o.store.reference(referenceID))
            #expect(updated.bookmarkData != original.bookmarkData)
            #expect(canonical(updated.lastResolvedPath) == canonical(moved.path))
            #expect(try await o.revisionCount(of: created.id) == 1)
            #expect(try await o.revisionCount() == 9)

            await o.model.select(o.project)
            let sourceBackend = try #require(o.model.loadedSnapshot?.node(named: "backend"))
            #expect(sourceBackend.referenceID == referenceID)
            #expect(canonical(try await o.store.reference(referenceID)?.lastResolvedPath) == canonical(moved.path))
            #expect(try await o.store.snapshot(revisionID: try await o.revisionID(8)).node(named: "backend")?.recordedPath == backend.recordedPath)
        }
    }

    // MARK: 경계

    @Test("시트를 연 채 다른 Board를 고르면 시트가 닫히고 뒤늦은 확정은 쓰이지 않는다")
    func switchingBoardClosesSheet() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            #expect(o.model.duplication != nil)
            await o.model.select(o.other)
            #expect(o.model.duplication == nil)
            await o.model.confirmDuplicate()
            #expect(o.boardCount == 2)
        }
    }

    @Test("새 Board를 만든 뒤 원본 Board로 돌아가면 과거 모드가 아니다")
    func returningToSourceIsCurrent() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(8)
            o.model.beginDuplicate()
            await o.model.confirmDuplicate()
            #expect(o.boardCount == 3)
            await o.model.select(o.project)
            #expect(!o.model.isViewingPast)
            #expect(o.history.selection == .current)
            #expect(o.model.loadedSnapshot?.projectName == "서비스 A")
        }
    }
}
