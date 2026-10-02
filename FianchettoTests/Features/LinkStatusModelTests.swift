import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("연결 상태 표시와 재연결 화면 (W15)")
struct LinkStatusModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let other: UUID
        let directory: URL
        let memoURL: URL
        let backendURL: URL
        var model: BoardBrowserModel { harness.model }
        var bookmarks: ScriptedBookmarkSystem { harness.bookmarks }
        var store: ProjectStore { model.openedStore!.store }

        func id(_ name: String) throws -> UUID {
            try #require(model.loadedSnapshot?.node(named: name)).id
        }
    }

    static let memo = "설계 메모.md"

    /// "서비스 A" 최상위: Bishop 파일 "설계 메모.md", Bishop 폴더 "backend", 웹 링크 "API 명세", 그룹 "개발". 다른 Board "다른 Board"가 있다.
    private func opened(_ directory: URL, archived: Bool = false, select: Bool = true) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let memo = try TargetFiles.file(directory, "targets/\(Self.memo)", contents: "memo")
        let backend = try TargetFiles.folder(directory, "targets/backend")
        var ids = (UUID(), UUID())
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [memo, backend]))
            _ = try await seed.service.apply(.addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil), to: board)
            _ = try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board)
            let other = try await makeBoard(seed, "다른 Board")
            if archived { try await seed.store.setArchived(board, at: date(100)) }
            ids = (board, other)
        }
        await harness.model.start()
        if select { await harness.model.select(ids.0) }
        return Opened(harness: harness, project: ids.0, other: ids.1, directory: directory, memoURL: memo, backendURL: backend)
    }

    private func revisionCount(_ o: Opened) async throws -> Int {
        try await o.store.revisionSummaries(projectID: o.project).count
    }

    private func reference(_ o: Opened, _ name: String) async throws -> ResourceReferenceRecord {
        let node = try #require(try await o.store.currentSnapshot(projectID: o.project).node(named: name))
        let referenceID = try #require(node.referenceID)
        return try #require(try await o.store.reference(referenceID))
    }

    private func canonical(_ path: String?) -> String? {
        path.map { URL(filePath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
    }

    private func moveMemo(_ o: Opened) throws -> URL {
        let moved = o.directory.appending(path: "targets/moved/\(Self.memo)")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: o.memoURL, to: moved)
        return moved
    }

    private static let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
    private static let noEvidence = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)

    /// 범위 있는 해석만 거부해 "권한 필요"로 보이게 한다. 범위 없는 해석(식별자 확인)은 실제로 된다.
    private func showAccessRequired(_ o: Opened) async throws {
        o.bookmarks.failResolution(with: Self.denied, scopedOnly: true)
        await o.model.selectNode(try o.id(Self.memo))
        #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == .accessRequired)
    }

    // MARK: 확인 시점과 표시

    @Test("[W15-no-check-on-open] 저장소를 열고 Board를 고르기만 해서는 연결 상태를 확인하지 않는다")
    func noCheckOnOpen() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, select: false)
            try FileManager.default.removeItem(at: o.memoURL)
            await o.model.select(o.project)

            #expect(o.bookmarks.scopedResolutions.isEmpty)
            for node in try #require(o.model.loadedSnapshot).nodes {
                #expect(o.model.displayedStatus(of: node.id) == nil)
            }
        }
    }

    enum Problem: String, CaseIterable, Sendable { case deleted, denied, volumeDetached, noEvidence }

    @Test("[W15-check-on-select] Bishop을 선택하면 상태를 확인해 기호와 문구로 보이고 기록·참조는 그대로다", .tags(.A12, .A02), arguments: Problem.allCases)
    func checkOnSelect(problem: Problem) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            switch problem {
            case .deleted: try FileManager.default.removeItem(at: o.memoURL)
            case .denied: o.bookmarks.failResolution(with: Self.denied, scopedOnly: true)
            case .volumeDetached: o.bookmarks.failResolution(with: Self.noEvidence, volumeUnmounted: true)
            case .noEvidence: o.bookmarks.failResolution(with: Self.noEvidence)
            }
            let memo = try o.id(Self.memo)
            let before = (try await revisionCount(o), try await o.store.currentSnapshot(projectID: o.project), try await reference(o, Self.memo))

            await o.model.selectNode(memo)

            let (expected, text): (LinkStatus, String) = switch problem {
            case .deleted: (.missing, "대상 없음")
            case .denied: (.accessRequired, "권한 필요")
            case .volumeDetached: (.volumeUnavailable, "볼륨 연결 필요")
            case .noEvidence: (.checkFailed, "확인 실패")
            }
            #expect(o.model.displayedStatus(of: memo) == expected)
            #expect(o.model.statusText(expected) == text)
            #expect(LinkStatusPresentation.of(expected) != nil)
            let node = try #require(o.model.loadedSnapshot?.node(named: Self.memo))
            #expect(o.model.accessibilityLabel(for: node).contains(text))
            #expect(o.model.inspector?.status == text)
            #expect(try await revisionCount(o) == before.0)
            #expect(try await o.store.currentSnapshot(projectID: o.project) == before.1)
            #expect(try await reference(o, Self.memo) == before.2)
        }
    }

    @Test("[W15-healthy-no-badge] 정상인 Bishop은 한 번 해석하고 상태 표시가 없다")
    func healthyNoBadge() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let backend = try o.id("backend")

            await o.model.selectNode(backend)

            #expect(o.bookmarks.scopedResolutions == ["backend"])
            #expect(o.model.displayedStatus(of: backend) == nil)
            #expect(LinkStatusPresentation.of(.healthy) == nil)
            let node = try #require(o.model.loadedSnapshot?.node(named: "backend"))
            #expect(o.model.accessibilityLabel(for: node) == "backend, Bishop")
            #expect(o.model.inspector?.status == nil)
        }
    }

    @Test("[W15-non-bishop-not-checked] 그룹·웹 링크를 선택하면 확인하지 않는다")
    func nonBishopNotChecked() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.selectNode(try o.id("개발"))
            await o.model.selectNode(try o.id("API 명세"))
            #expect(o.bookmarks.scopedResolutions.isEmpty)
            #expect(o.model.selectedNodeID == (try o.id("API 명세")))
        }
    }

    @Test("[W15-open-updates-status] 열기 실패는 상태로 남고 열기에 성공하면 상태 표시가 사라진다", arguments: [false, true])
    func openUpdatesStatus(recovered: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let memo = try o.id(Self.memo)
            if recovered {
                try await showAccessRequired(o)
                o.bookmarks.clearResolutionFailure()
            } else {
                try FileManager.default.removeItem(at: o.memoURL)
                o.model.selectedNodeID = memo
            }

            await o.model.openSelected()

            if recovered {
                #expect(o.harness.launcher.opened.count == 1)
                #expect(o.model.displayedStatus(of: memo) == nil)
            } else {
                #expect(o.model.linkNotice?.kind == .openFailed(.unreachable(.missing)))
                #expect(o.model.displayedStatus(of: memo) == .missing)
            }
        }
    }

    @Test("[W15-refresh-all] 상태 새로고침은 Bishop마다 한 번씩만 확인하고 기록하지 않는다", .tags(.A12))
    func refreshAll() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.memoURL)
            let before = try await revisionCount(o)

            await o.model.refreshStatuses()

            #expect(o.bookmarks.scopedResolutions.sorted() == ["backend", Self.memo])
            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == .missing)
            #expect(o.model.displayedStatus(of: try o.id("backend")) == nil)
            #expect(o.model.displayedStatus(of: try o.id("API 명세")) == nil)
            #expect(o.model.displayedStatus(of: try o.id("개발")) == nil)
            #expect(try await revisionCount(o) == before)
        }
    }

    @Test("[W15-status-clears] 다시 확인해 정상이면 이전 상태 표시가 사라진다")
    func statusClears() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await showAccessRequired(o)
            o.bookmarks.clearResolutionFailure()

            await o.model.refreshStatuses()

            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == nil)
        }
    }

    @Test("[W15-status-per-board] Board를 바꾸면 이전 상태 표시가 남지 않는다")
    func statusPerBoard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.memoURL)
            await o.model.selectNode(try o.id(Self.memo))
            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == .missing)

            await o.model.select(o.other)
            await o.model.select(o.project)

            for node in try #require(o.model.loadedSnapshot).nodes {
                #expect(o.model.displayedStatus(of: node.id) == nil)
            }
        }
    }

    @Test("[W15-late-result-discarded] Board를 바꾼 뒤 끝난 확인 결과는 버린다")
    func lateResultDiscarded() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.memoURL)
            let memo = try o.id(Self.memo)
            let gate = o.bookmarks.pauseNextResolution()

            let check = Task { await o.model.selectNode(memo) }
            await gate.entered()
            await o.model.select(o.other)
            gate.release()
            await check.value

            #expect(o.model.displayedStatus(of: memo) == nil)
            await o.model.select(o.project)
            #expect(o.model.displayedStatus(of: memo) == nil)
        }
    }

    // MARK: 접근 정보 갱신

    enum Refresh: String, CaseIterable, Sendable { case select, open, selectArchived }

    @Test("[W15-refresh-access-info] 옮겨진 대상을 확인하면 같은 참조에 접근 정보를 저장하고 기록하지 않는다", .tags(.A02), arguments: Refresh.allCases)
    func refreshAccessInfo(way: Refresh) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: way == .selectArchived)
            let original = try await reference(o, Self.memo)
            let recorded = try #require(o.model.loadedSnapshot?.node(named: Self.memo)).recordedPath
            let before = try await revisionCount(o)
            let moved = try moveMemo(o)
            let memo = try o.id(Self.memo)

            switch way {
            case .select, .selectArchived: await o.model.selectNode(memo)
            case .open:
                o.model.selectedNodeID = memo
                await o.model.openSelected()
            }

            #expect(o.model.displayedStatus(of: memo) == nil)
            let updated = try await reference(o, Self.memo)
            #expect(updated.id == original.id)
            #expect(updated.initialPath == original.initialPath)
            #expect(updated.bookmarkData != original.bookmarkData)
            #expect(canonical(updated.lastResolvedPath) == canonical(moved.path))
            let stored = try await o.store.currentSnapshot(projectID: o.project)
            #expect(stored.node(named: Self.memo)?.recordedPath == recorded)
            #expect(try await revisionCount(o) == before)
            #expect(o.model.linkNotice == nil)
        }
    }

    @Test("[W15-refresh-failed-keeps-reference] 새 접근 정보를 만들지 못하면 참조를 그대로 둔다")
    func refreshFailedKeepsReference() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let original = try await reference(o, Self.memo)
            let before = try await revisionCount(o)
            _ = try moveMemo(o)
            o.bookmarks.fail([Self.memo])

            await o.model.selectNode(try o.id(Self.memo))

            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == nil)
            #expect(try await reference(o, Self.memo) == original)
            #expect(try await revisionCount(o) == before)
        }
    }

    @Test("[W15-access-info-save-failure] 접근 정보 갱신 저장이 실패해도 상태·기록·참조는 그대로다")
    func accessInfoSaveFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let original = try await reference(o, Self.memo)
            let before = try await revisionCount(o)
            _ = try moveMemo(o)
            o.harness.fault.failNext()

            await o.model.selectNode(try o.id(Self.memo))

            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == nil)
            #expect(o.model.linkNotice == nil)
            #expect(try await reference(o, Self.memo) == original)
            #expect(try await revisionCount(o) == before)
        }
    }

    // MARK: 다시 선택

    @Test("[W15-reselect-same-target] 같은 대상을 다시 선택하면 같은 참조의 접근 정보만 바꾸고 기록하지 않는다", .tags(.A12, .A02))
    func reselectSameTarget() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await showAccessRequired(o)
            let original = try await reference(o, Self.memo)
            let before = try await revisionCount(o)
            o.harness.picker.replacementResults = [o.memoURL]

            await o.model.reselectSelectedTarget()

            #expect(o.harness.picker.replacementKinds == [.file])
            #expect(o.model.replacement == nil)
            #expect(o.model.linkNotice == nil)
            let updated = try await reference(o, Self.memo)
            #expect(updated.id == original.id)
            #expect(updated.initialPath == original.initialPath)
            #expect(canonical(updated.lastResolvedPath) == canonical(o.memoURL.path))
            #expect(try await revisionCount(o) == before)
            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == nil)
        }
    }

    enum Different: String, CaseIterable, Sendable { case deniedOtherFile, deletedOtherFile, unresolvableSameFile }

    @Test("[W15-reselect-goes-to-replacement] 다른 대상이거나 판정 불가면 연결 대상 변경 확인 창을 연다", .tags(.A12), arguments: Different.allCases)
    func reselectGoesToReplacement(situation: Different) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let other = try TargetFiles.file(directory, "targets/other.md", contents: "other")
            switch situation {
            case .deniedOtherFile:
                try await showAccessRequired(o)
                o.harness.picker.replacementResults = [other]
            case .deletedOtherFile:
                try FileManager.default.removeItem(at: o.memoURL)
                await o.model.selectNode(try o.id(Self.memo))
                o.harness.picker.replacementResults = [other]
            case .unresolvableSameFile:
                o.bookmarks.failResolution(with: Self.noEvidence)
                await o.model.selectNode(try o.id(Self.memo))
                o.harness.picker.replacementResults = [o.memoURL]
            }
            let before = try await revisionCount(o)

            await o.model.reselectSelectedTarget()

            let preview = try #require(o.model.replacement)
            let warning = o.model.replacementPresentation(preview).warning
            switch situation {
            case .deniedOtherFile: #expect(preview.identity == .differentTarget && warning == nil)
            case .deletedOtherFile, .unresolvableSameFile:
                #expect(preview.identity == .undetermined)
                #expect(warning == o.model.undeterminedText)
            }
            #expect(try await revisionCount(o) == before)
        }
    }

    @Test("[W15-replacement-confirm] 이어진 대상 변경을 확인하면 새 참조와 revision 하나가 생기고 상태 표시가 사라진다", .tags(.A12))
    func replacementConfirm() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let other = try TargetFiles.file(directory, "targets/other.md", contents: "other")
            try FileManager.default.removeItem(at: o.memoURL)
            await o.model.selectNode(try o.id(Self.memo))
            let original = try await reference(o, Self.memo)
            let before = try await revisionCount(o)
            o.harness.picker.replacementResults = [other]
            await o.model.reselectSelectedTarget()

            await o.model.confirmReplacement()

            let summaries = try await o.store.revisionSummaries(projectID: o.project)
            #expect(summaries.count == before + 1)
            #expect(summaries.last?.cause == .edited(.replaceTarget))
            #expect(try await reference(o, Self.memo).id != original.id)
            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == nil)
        }
    }

    @Test("[W15-replacement-cancel] 이어진 대상 변경을 취소하면 아무것도 바뀌지 않는다")
    func replacementCancel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let other = try TargetFiles.file(directory, "targets/other.md", contents: "other")
            try FileManager.default.removeItem(at: o.memoURL)
            await o.model.selectNode(try o.id(Self.memo))
            let original = try await reference(o, Self.memo)
            let before = try await revisionCount(o)
            o.harness.picker.replacementResults = [other]
            await o.model.reselectSelectedTarget()

            o.model.cancelReplacement()

            #expect(o.model.replacement == nil)
            #expect(try await revisionCount(o) == before)
            #expect(try await reference(o, Self.memo) == original)
            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == .missing)
        }
    }

    @Test("[W15-reselect-cancel] 다시 선택 창을 취소하면 아무것도 바뀌지 않는다")
    func reselectCancel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.memoURL)
            await o.model.selectNode(try o.id(Self.memo))
            let original = try await reference(o, Self.memo)
            let before = try await revisionCount(o)
            o.harness.picker.replacementResults = [nil]

            await o.model.reselectSelectedTarget()

            #expect(o.harness.picker.replacementKinds == [.file])
            #expect(o.model.replacement == nil)
            #expect(o.model.linkNotice == nil)
            #expect(try await revisionCount(o) == before)
            #expect(try await reference(o, Self.memo) == original)
            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == .missing)
        }
    }

    @Test("[W15-reselect-save-failure] 같은 대상 접근 복구 저장이 실패하면 안내하고 참조·기록·상태를 유지한다")
    func reselectSaveFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await showAccessRequired(o)
            let original = try await reference(o, Self.memo)
            let before = try await revisionCount(o)
            o.harness.picker.replacementResults = [o.memoURL]
            o.harness.fault.failNext()

            await o.model.reselectSelectedTarget()

            #expect(o.model.linkNotice?.kind == .saveFailed)
            #expect(try await reference(o, Self.memo) == original)
            #expect(try await revisionCount(o) == before)
            #expect(o.model.displayedStatus(of: try o.id(Self.memo)) == .accessRequired)
        }
    }

    // MARK: 보관된 Board

    enum Archived: String, CaseIterable, Sendable { case select, refresh, reselectSame, reselectOtherDenied, reselectOtherDeleted }

    @Test("[W15-archived] 보관된 Board에서는 확인과 같은 대상 복구는 되고 대상 변경은 보관 안내로 막는다", arguments: Archived.allCases)
    func archived(action: Archived) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            let memo = try o.id(Self.memo)
            let other = try TargetFiles.file(directory, "targets/other.md", contents: "other")
            switch action {
            case .select, .refresh, .reselectOtherDeleted:
                try FileManager.default.removeItem(at: o.memoURL)
            case .reselectSame, .reselectOtherDenied:
                try await showAccessRequired(o)
            }
            if action == .reselectOtherDeleted { await o.model.selectNode(memo) }
            let original = try await reference(o, Self.memo)
            let before = try await revisionCount(o)

            switch action {
            case .select:
                await o.model.selectNode(memo)
            case .refresh:
                await o.model.refreshStatuses()
            case .reselectSame:
                o.harness.picker.replacementResults = [o.memoURL]
                await o.model.reselectSelectedTarget()
            case .reselectOtherDenied, .reselectOtherDeleted:
                o.harness.picker.replacementResults = [other]
                await o.model.reselectSelectedTarget()
            }

            #expect(try await revisionCount(o) == before)
            #expect(o.model.replacement == nil)
            switch action {
            case .select, .refresh:
                #expect(o.model.displayedStatus(of: memo) == .missing)
                #expect(o.model.linkNotice == nil)
            case .reselectSame:
                #expect(o.model.displayedStatus(of: memo) == nil)
                #expect(o.model.linkNotice == nil)
                #expect(canonical(try await reference(o, Self.memo).lastResolvedPath) == canonical(o.memoURL.path))
            case .reselectOtherDenied, .reselectOtherDeleted:
                #expect(o.model.linkNotice?.kind == .archived)
                #expect(try await reference(o, Self.memo) == original)
            }
        }
    }

    enum NotApplicable: String, CaseIterable, Sendable { case none, group, webLink }

    @Test("[W15-reselect-not-applicable] 선택 없음·그룹·웹 링크의 다시 선택은 아무 일도 하지 않는다", arguments: NotApplicable.allCases)
    func reselectNotApplicable(selection: NotApplicable) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = switch selection {
            case .none: nil
            case .group: try o.id("개발")
            case .webLink: try o.id("API 명세")
            }
            #expect(!o.model.canReselectSelected)

            await o.model.reselectSelectedTarget()

            #expect(o.harness.picker.replacementKinds.isEmpty)
            #expect(o.model.linkNotice == nil)
            #expect(o.model.replacement == nil)
        }
    }

    @Test("[W15-commands] 상태가 보이는 Bishop의 상세 영역은 상태 문구와 다시 선택·상태 새로고침을 보인다", .tags(.A12, .A02))
    func inspectorCommands() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.selectNode(try o.id("backend"))
            #expect(o.model.canReselectSelected)
            #expect(o.model.inspector?.status == nil)

            try FileManager.default.removeItem(at: o.memoURL)
            await o.model.selectNode(try o.id(Self.memo))
            #expect(o.model.canReselectSelected)
            #expect(o.model.inspector?.status == "대상 없음")
        }
    }
}
