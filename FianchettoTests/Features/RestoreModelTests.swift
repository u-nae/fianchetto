import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 과거 구성으로 복원하는 화면 흐름: 시트 상태, 켜짐 판단 값, 시작·취소·확정, 안내(W20).
@MainActor
@Suite("과거 구성으로 복원 화면 흐름 (W20)")
struct RestoreModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let other: UUID
        let legacyURL: URL
        let v2URL: URL
        var model: BoardBrowserModel { harness.model }
        var history: HistoryPanelModel { harness.model.history }
        var store: ProjectStore { model.openedStore!.store }

        func revisionID(_ sequence: Int) async throws -> UUID {
            try await summary(sequence).id
        }

        func summary(_ sequence: Int, of board: UUID? = nil) async throws -> RevisionSummary {
            try #require(try await store.revisionSummaries(projectID: board ?? project).first { $0.sequence == sequence })
        }

        func revisionCount(of board: UUID? = nil) async throws -> Int {
            try await store.revisionSummaries(projectID: board ?? project).count
        }

        func currentRevision() async throws -> RevisionSummary {
            let id = try #require(try await store.project(project)?.currentRevisionID)
            return try #require(try await store.revisionSummaries(projectID: project).first { $0.id == id })
        }

        /// 이력 탭을 열고 그 순번의 구성을 본다.
        func viewPast(_ sequence: Int) async throws {
            await model.selectInspectorTab(.history)
            await history.select(.revision(try await revisionID(sequence)))
        }

        /// 두 대상 폴더의 파일 이름과 표식 파일 내용.
        func targetFiles() throws -> [String: String] {
            var result: [String: String] = [:]
            for folder in [legacyURL, v2URL] {
                for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() {
                    result[folder.appending(path: name).path] = try String(contentsOf: folder.appending(path: name), encoding: .utf8)
                }
            }
            return result
        }
    }

    /// 1 Board 만들기("서비스 알파"), 2 Bishop backend(legacy) 추가, 3 대상 교체(v2), 4 Wing "문서", 5 이름 "서비스 A".
    /// 다른 Board "서비스 B"가 있다. 두 대상 폴더에는 표식 파일이 하나씩 있다.
    private func opened(_ directory: URL, archived: Bool = false, corruptCurrent: Bool = false) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let legacy = try TargetFiles.folder(directory, "targets/legacy/backend")
        let v2 = try TargetFiles.folder(directory, "targets/v2/backend")
        _ = try TargetFiles.file(directory, "targets/legacy/backend/marker.txt", contents: "legacy marker")
        _ = try TargetFiles.file(directory, "targets/v2/backend/marker.txt", contents: "v2 marker")
        var ids = (fixedID(1), fixedID(2))
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 알파")
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [legacy]))
            let backend = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "backend")).id
            let replacement = TargetReplacementService(bookmarks: BookmarkAdapter(system: seed.bookmarks), configuration: seed.service)
            let preview = try await replacement.preview(projectID: board, nodeID: backend, newURL: v2).get()
            _ = try await replacement.confirm(preview)
            _ = try await seed.service.apply(.addGroup(name: "문서", parentID: nil, position: nil), to: board)
            _ = try await seed.service.apply(.renameProject("서비스 A"), to: board)
            let other = try await makeBoard(seed, "서비스 B")
            if archived { try await seed.store.setArchived(board, at: date(100)) }
            ids = (board, other)
        }
        if corruptCurrent {
            let board = ids.0
            try withStore(at: harness.url) { adapter in
                let models = try adapter.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>())
                let model = try #require(models.first { $0.sequence == 5 && $0.projectID == board })
                model.snapshotData = Data("{\"schemaVersion\":1,".utf8)
                try adapter.save()
            }
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, project: ids.0, other: ids.1, legacyURL: legacy, v2URL: v2)
    }

    // MARK: 시트 열기

    @Test("[W20-restore-menu-opens-sheet] 과거 구성에서 복원을 시작하면 차이 확인 시트가 열리고 revision은 생기지 않는다", .tags(.A08))
    func opensSheet() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            let preview = try #require(o.model.restorePreview)
            #expect(preview.title == "#2 구성으로 복원")
            #expect(preview.beforeText == "현재 구성")
            #expect(preview.afterText.hasPrefix("#2 · "))
            #expect(!preview.isIdentical)
            #expect(o.model.canConfirmRestore)
            #expect(try await o.revisionCount() == 5)
        }
    }

    @Test("시트가 열려 있는 동안에는 복원을 다시 시작할 수 없고 시트는 그대로다")
    func beginWhileSheetOpen() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            let first = try #require(o.model.restorePreview)
            #expect(!o.model.canRestoreShown)
            o.model.beginRestore()
            #expect(o.model.restorePreview == first)
            #expect(o.model.restorePreview?.isSaving == first.isSaving)
        }
    }

    @Test("시트를 연 채 현재 구성으로 돌아가 확정하면 이전 구성 기준의 상태 확인 결과가 남지 않고 접근 정보를 해석하지 않는다")
    func confirmFromCurrentClearsStatuses() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            let backendID = try #require(o.model.shownSnapshot?.node(named: "backend")).id
            o.model.beginRestore()
            await o.model.selectNode(backendID)
            #expect(o.model.linkStatuses[backendID] != nil)
            await o.model.returnToCurrent()
            let resolutions = o.harness.bookmarks.scopedResolutions.count
            await o.model.confirmRestore()
            #expect(try await o.revisionCount() == 6)
            #expect(o.model.linkStatuses.isEmpty)
            #expect(o.harness.bookmarks.scopedResolutions.count == resolutions)
        }
    }

    @Test("[W20-no-menu-on-current] 현재 구성을 볼 때는 복원을 시작할 수 없다")
    func noMenuOnCurrent() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(!o.model.isViewingPast)
            #expect(!o.model.canRestoreShown)
            o.model.beginRestore()
            #expect(o.model.restorePreview == nil)
        }
    }

    @Test("[W20-archived-disables-restore-only] 보관된 Board의 과거 구성에서는 복원만 꺼지고 비교는 켜진다")
    func archivedDisablesRestoreOnly() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            try await o.viewPast(2)
            #expect(o.model.isViewingPast)
            #expect(!o.model.canRestoreShown)
            #expect(o.model.canCompareWithCurrent)
            o.model.beginRestore()
            #expect(o.model.restorePreview == nil)
        }
    }

    enum Situation: CaseIterable, CustomTestStringConvertible {
        case current, past, comparing, archivedPast
        var testDescription: String {
            switch self {
            case .current: "현재 구성"
            case .past: "과거 구성"
            case .comparing: "비교 중"
            case .archivedPast: "보관된 Board의 과거 구성"
            }
        }
    }

    @Test("[W20-file-menu-enablement] 복원 명령은 과거 구성을 볼 때만 켜진다", arguments: Situation.allCases)
    func enablement(_ situation: Situation) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: situation == .archivedPast)
            switch situation {
            case .current: break
            case .past, .archivedPast: try await o.viewPast(2)
            case .comparing:
                try await o.viewPast(2)
                await o.model.compareWithCurrent()
                #expect(o.model.isComparing)
            }
            let expected = situation == .past
            #expect(o.model.canRestoreShown == expected)
            o.model.beginRestore()
            #expect((o.model.restorePreview != nil) == expected)
        }
    }

    @Test("[W20-sheet-identical-no-button] 현재와 같은 구성이면 확정할 수 없고 닫아도 revision이 생기지 않는다")
    func identical() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(5)
            o.model.beginRestore()
            let preview = try #require(o.model.restorePreview)
            #expect(preview.isIdentical)
            #expect(!o.model.canConfirmRestore)
            await o.model.confirmRestore()
            #expect(try await o.revisionCount() == 5)
            o.model.cancelRestore()
            #expect(o.model.restorePreview == nil)
            #expect(try await o.revisionCount() == 5)
        }
    }

    @Test("[W20-sheet-no-file-access] 차이 확인은 파일 시스템 접근과 연결 상태 확인을 하지 않는다")
    func noFileAccess() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            let resolutions = o.harness.bookmarks.scopedResolutions.count
            let statuses = o.model.linkStatuses
            o.model.beginRestore()
            #expect(o.model.restorePreview != nil)
            #expect(o.harness.bookmarks.scopedResolutions.count == resolutions)
            #expect(o.harness.launcher.opened.isEmpty)
            #expect(o.harness.launcher.revealed.isEmpty)
            #expect(o.model.linkStatuses == statuses)
        }
    }

    @Test("[W20-sheet-keyboard-accessibility] 시트의 제목·요약·변경 목록은 순서대로 읽을 문구를 가진다")
    func accessibility() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            let preview = try #require(o.model.restorePreview)
            #expect(preview.title == "#2 구성으로 복원")
            #expect(preview.summaryText == "변화 2개 · Board 이름 변경")
            let labels = preview.rows.map(\.accessibilityLabel)
            #expect(labels.count == 2)
            #expect(labels[0].hasPrefix("backend, 대상 교체 "))
            #expect(labels[0].contains("/v2/backend → "))
            #expect(labels[0].hasSuffix("/legacy/backend"))
            #expect(labels[1] == "문서, 제거됨")
        }
    }

    // MARK: 취소와 확정

    @Test("[W20-cancel-keeps-past-view] 취소하면 revision이 생기지 않고 과거 구성 보기가 이어진다")
    func cancelKeepsPast() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            o.model.cancelRestore()
            #expect(o.model.restorePreview == nil)
            #expect(o.model.isViewingPast)
            #expect(o.history.selectedRevisionID == (try await o.revisionID(2)))
            #expect(try await o.revisionCount() == 5)
        }
    }

    @Test("[W20-confirm-creates-restored-revision] 확정하면 복원된 구성이 현재가 되고 현재 구성 보기로 돌아간다", .tags(.A08))
    func confirmCreatesRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            await o.model.confirmRestore()
            let sourceID = try await o.revisionID(2)
            #expect(try await o.revisionCount() == 6)
            let current = try await o.currentRevision()
            #expect(current.sequence == 6)
            #expect(current.cause == .restored(from: sourceID))
            #expect(o.model.loadedSnapshot?.projectName == "서비스 알파")
            #expect(o.model.loadedSnapshot == (try await o.store.snapshot(revisionID: sourceID)))
            #expect(!o.model.isViewingPast)
            #expect(o.history.selection == .current)
            let row = try #require(o.history.rows.first)
            #expect(row.summary.sequence == 6)
            #expect(o.history.causeText(row) == "#2에서 복원")
            #expect(o.model.restorePreview == nil)
            #expect(o.model.board(named: "서비스 알파") != nil)
        }
    }

    @Test("[W20-restores-unreachable-items] 접근할 수 없는 항목도 그대로 복원하고 상태는 고를 때 확인한다")
    func unreachableItems() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.bookmarks.failResolution(with: NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError))
            try await o.viewPast(2)
            let targetReference = try #require(o.model.shownSnapshot?.node(named: "backend")?.referenceID)
            let backendID = try #require(o.model.shownSnapshot?.node(named: "backend")).id
            o.model.beginRestore()
            let resolutions = o.harness.bookmarks.scopedResolutions.count
            await o.model.confirmRestore()
            #expect(o.harness.bookmarks.scopedResolutions.count == resolutions)
            #expect(o.model.loadedSnapshot?.node(named: "backend")?.referenceID == targetReference)
            await o.model.selectNode(backendID)
            #expect(o.model.displayedStatus(of: backendID) == .missing)
            #expect(o.model.canReselectSelected)
            #expect(o.model.canRefreshStatuses)
            #expect(try await o.revisionCount() == 6)
        }
    }

    @Test("[W20-save-failure-keeps-current] 저장이 실패하면 이전 구성이 유지되고 시트가 닫히며 저장 실패를 알린다")
    func saveFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            o.harness.fault.failNext()
            await o.model.confirmRestore()
            #expect(try await o.revisionCount() == 5)
            #expect(try await o.currentRevision().sequence == 5)
            #expect(o.model.restorePreview == nil)
            #expect(o.model.linkNotice == BoardBrowserModel.LinkNotice(kind: .saveFailed, request: nil, action: .restore))
            #expect(o.model.isViewingPast)
            #expect(o.history.selectedRevisionID == (try await o.revisionID(2)))
            o.model.dismissLinkNotice()
            o.model.beginRestore()
            await o.model.confirmRestore()
            #expect(try await o.revisionCount() == 6)
        }
    }

    @Test("[W20-no-disk-side-effects] 복원은 연결 대상 원본을 읽거나 바꾸지 않는다", .tags(.A08))
    func noDiskSideEffects() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try o.targetFiles()
            #expect(before.count == 2)
            try await o.viewPast(2)
            o.model.beginRestore()
            await o.model.confirmRestore()
            #expect(try await o.revisionCount() == 6)
            #expect(try o.targetFiles() == before)
            #expect(o.harness.launcher.opened.isEmpty)
            #expect(o.harness.launcher.revealed.isEmpty)
            #expect(o.harness.actions.revealed.isEmpty)
        }
    }

    // MARK: 경계

    @Test("시트를 연 채 다른 Board를 고르면 시트가 닫히고 그 Board에는 쓰지 않는다")
    func switchingBoardClosesSheet() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            #expect(o.model.restorePreview != nil)
            await o.model.select(o.other)
            #expect(o.model.restorePreview == nil)
            await o.model.confirmRestore()
            #expect(try await o.revisionCount() == 5)
            #expect(try await o.revisionCount(of: o.other) == 1)
        }
    }

    // 가드가 있으면 첫 호출만 서비스에 닿아 실패한다. 가드가 없으면 두 번째 호출이 성공해 revision 6이 생긴다.
    @Test("확정을 연달아 두 번 요청해도 revision은 하나만 생긴다")
    func doubleConfirm() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            o.harness.fault.failNext(1)
            async let a: Void = o.model.confirmRestore()
            async let b: Void = o.model.confirmRestore()
            _ = await (a, b)
            #expect(try await o.revisionCount() == 5)
            #expect(try await o.currentRevision().sequence == 5)
            #expect(o.model.restorePreview == nil)
            #expect(o.model.linkNotice == BoardBrowserModel.LinkNotice(kind: .saveFailed, request: nil, action: .restore))
        }
    }

    @Test("시트를 연 뒤 Board가 보관되면 확정이 거부되고 보관 안내를 보인다")
    func archivedAfterOpen() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast(2)
            o.model.beginRestore()
            try await o.store.setArchived(o.project, at: date(900))
            await o.model.confirmRestore()
            #expect(o.model.restorePreview == nil)
            #expect(o.model.linkNotice == BoardBrowserModel.LinkNotice(kind: .archived, request: nil, action: .restore))
            #expect(try await o.revisionCount() == 5)
            #expect(o.model.isViewingPast)
        }
    }

    @Test("현재 구성을 읽지 못한 Board에서는 복원 명령이 꺼진다")
    func unreadableCurrent() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, corruptCurrent: true)
            try await o.viewPast(2)
            #expect(o.model.isViewingPast)
            #expect(!o.model.canRestoreShown)
            o.model.beginRestore()
            #expect(o.model.restorePreview == nil)
        }
    }
}
