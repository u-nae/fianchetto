import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 구성 비교 화면(W19, PR ①: 공통 부분 + 통합 트리).
@MainActor
@Suite("구성 비교(W19)")
struct ComparisonModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let other: UUID
        let legacyURL: URL
        let v2URL: URL
        var model: BoardBrowserModel { harness.model }
        var history: HistoryPanelModel { harness.model.history }
        var comparison: ComparisonModel { harness.model.comparison }
        var store: ProjectStore { model.openedStore!.store }

        func revisionID(_ sequence: Int) async throws -> UUID {
            try #require(try await store.revisionSummaries(projectID: project).first { $0.sequence == sequence }).id
        }

        func revisionCount() async throws -> Int {
            try await store.revisionSummaries(projectID: project).count
        }

        func view(_ sequence: Int) async throws {
            await model.selectInspectorTab(.history)
            await history.select(.revision(try await revisionID(sequence)))
        }

        func row(named name: String) throws -> ComparisonRow {
            func search(_ rows: [ComparisonRow]) -> ComparisonRow? {
                for row in rows {
                    if row.node.displayName == name { return row }
                    if let found = search(row.children) { return found }
                }
                return nil
            }
            return try #require(search(comparison.rows))
        }

        func target(_ sequence: Int) async throws -> ComparisonTarget { .revision(try await revisionID(sequence)) }
    }

    /// "서비스 A" revision:
    /// 1 만들기, 2 Wing 개발, 3 개발 안 Bishop 폴더 backend(legacy), 4 웹 링크 "API 명세", 5 개발 안 Bishop 파일 notes.md,
    /// 6 개발 → 개발2, 7 개발2 → 개발(5와 내용이 같다), 8 backend 대상 → v2, 9 notes.md 제거, 10 Board 이름 → 서비스 Alpha. 현재는 10.
    /// 다른 Board "서비스 B"가 있다.
    private func opened(_ directory: URL, archived: Bool = false, loadGate: LoadGate? = nil) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"), loadGate: loadGate)
        let legacy = try TargetFiles.folder(directory, "targets/legacy/backend")
        let v2 = try TargetFiles.folder(directory, "targets/v2/backend")
        let notes = try TargetFiles.file(directory, "targets/notes.md")
        var ids = (UUID(), UUID())
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            let dev = try #require(try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board).committed)
                .snapshot.node(named: "개발")!.id
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: dev, position: nil, urls: [legacy]))
            _ = try await seed.service.apply(.addWebLink(name: "API 명세", url: "https://old.example.com", parentID: nil, position: nil), to: board)
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: dev, position: nil, urls: [notes]))
            _ = try await seed.service.apply(.renameNode(dev, "개발2"), to: board)
            _ = try await seed.service.apply(.renameNode(dev, "개발"), to: board)
            let backend = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "backend")).id
            let replacement = TargetReplacementService(bookmarks: BookmarkAdapter(system: seed.bookmarks), configuration: seed.service)
            _ = try await replacement.confirm(try await replacement.preview(projectID: board, nodeID: backend, newURL: v2).get())
            let noteID = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "notes.md")).id
            _ = try await seed.service.apply(.remove(noteID), to: board)
            _ = try await seed.service.apply(.renameProject("서비스 Alpha"), to: board)
            let other = try await makeBoard(seed, "서비스 B")
            if archived { try await seed.store.setArchived(board, at: date(100)) }
            ids = (board, other)
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, project: ids.0, other: ids.1, legacyURL: legacy, v2URL: v2)
    }

    private func canonical(_ url: URL?) -> String? {
        url.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
    }

    // MARK: 진입과 대상

    @Test("[W19-open-from-banner] '현재와 비교'는 고른 revision을 이전, 현재 구성을 이후로 비교를 연다", .tags(.A07))
    func openFromBanner() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(5)
            #expect(o.model.canCompareWithCurrent)
            await o.model.compareWithCurrent()
            #expect(o.model.isComparing)
            #expect(o.comparison.before == (try await o.target(5)))
            #expect(o.comparison.after == .current)
            #expect(o.comparison.targetText(try await o.target(5)).hasPrefix("#5 · "))
            #expect(o.comparison.targetText(.current) == "현재 구성")
        }
    }

    enum Record: String, CaseIterable, Sendable { case currentAndThree, pastFiveAndThree, pastFiveAndSeven, pastFiveAndCurrent }

    @Test("[W19-compare-this-record] [W19-current-row-compare] '이 기록과 비교'는 그 행과 지금 보는 구성을 순번 순서로 비교한다", arguments: Record.allCases)
    func compareRecord(record: Record) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let expected: (ComparisonTarget, ComparisonTarget)
            switch record {
            case .currentAndThree:
                await o.model.selectInspectorTab(.history)
                await o.model.compareRecord(.revision(try await o.revisionID(3)))
                expected = (try await o.target(3), .current)
            case .pastFiveAndThree:
                try await o.view(5)
                await o.model.compareRecord(.revision(try await o.revisionID(3)))
                expected = (try await o.target(3), try await o.target(5))
            case .pastFiveAndSeven:
                try await o.view(5)
                await o.model.compareRecord(.revision(try await o.revisionID(7)))
                expected = (try await o.target(5), try await o.target(7))
            case .pastFiveAndCurrent:
                try await o.view(5)
                await o.model.compareRecord(.current)
                expected = (try await o.target(5), .current)
            }
            #expect(o.comparison.before == expected.0)
            #expect(o.comparison.after == expected.1)
        }
    }

    @Test("[W19-entry-enablement] 비교 진입·닫기 명령의 켜짐 조건")
    func entryEnablement() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.selectInspectorTab(.history)
            #expect(!o.model.canCompareWithCurrent)
            #expect(!o.model.canCloseComparison)
            #expect(!o.model.canCompareRecord(.current))
            #expect(o.model.canCompareRecord(.revision(try await o.revisionID(5))))
            try await o.view(5)
            #expect(o.model.canCompareWithCurrent)
            #expect(!o.model.canCompareRecord(.revision(try await o.revisionID(5))))
            #expect(o.model.canCompareRecord(.current))
            await o.model.compareWithCurrent()
            #expect(!o.model.canCompareWithCurrent)
            #expect(o.model.canCloseComparison)
            #expect(!o.model.canCompareRecord(.revision(try await o.revisionID(7))))
        }
    }

    @Test("[W19-keyboard-two-revisions] [W19-target-menus] 행 고르기 → 현재와 비교 → 대상 메뉴로 임의의 두 revision을 고른 순서 그대로 비교한다")
    func targetMenus() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(7)
            await o.model.compareWithCurrent()
            await o.comparison.setAfter(try await o.target(5))
            #expect(o.comparison.before == (try await o.target(7)))
            #expect(o.comparison.after == (try await o.target(5)))
            #expect(o.comparison.targetChoices.map(\.sequence) == Array((1...10).reversed()))
            await o.comparison.setBefore(try await o.target(9))
            await o.comparison.setAfter(try await o.target(3))
            #expect(o.comparison.before == (try await o.target(9)))
            #expect(o.comparison.after == (try await o.target(3)))
            // 순번 9 → 순번 3(거꾸로 고른 그대로): 순번 4에서 추가된 웹 링크는 '제거됨'으로 보인다.
            #expect(try o.row(named: "API 명세").kinds == [.removed])
        }
    }

    @Test("[W19-same-target-empty] [W19-no-change-empty] 같은 대상이면 '같은 구성입니다', 다른 revision인데 같으면 '변화 없음'이다", .tags(.A07))
    func emptyStates() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(5)
            await o.model.compareWithCurrent()
            await o.comparison.setAfter(try await o.target(5))
            #expect(o.comparison.isSameTarget)
            #expect(!o.comparison.hasNoChange)
            await o.comparison.setAfter(try await o.target(7))
            #expect(!o.comparison.isSameTarget)
            #expect(o.comparison.hasNoChange)
        }
    }

    @Test("[W19-board-rename-summary] [W19-summary-suffixes] [W19-reorder-hidden-zero] 요약 문구와 접미 순서")
    func summaryTexts() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(9)
            await o.model.compareWithCurrent()
            #expect(o.comparison.summaryText == "Board 이름 변경")
            #expect(!o.comparison.hasNoChange)
            #expect(o.comparison.showsBoardNameRow)
            await o.comparison.setBefore(try await o.target(8))
            #expect(o.comparison.summaryText == "변화 1개 · Board 이름 변경")
            await o.comparison.setBefore(try await o.target(5))
            await o.comparison.setAfter(try await o.target(6))
            #expect(o.comparison.summaryText == "변화 1개")
        }
    }

    @Test("[W19-reorder-hidden-zero] [W19-summary-suffixes] 순서 변경을 숨기면 '변화 0개 · 순서 변경 N개 숨김'이고 거르면 '표시할 변화 없음'이다")
    func hiddenReorderSummary() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            // 순서만 바뀐 revision 11을 더한다: 최상위 "API 명세"를 "개발" 앞으로.
            let api = try #require(o.model.loadedSnapshot?.node(named: "API 명세")).id
            await o.model.requestMove(api, toParent: nil, position: 0)
            try await o.view(10)
            await o.model.compareWithCurrent()
            #expect(o.comparison.summaryText == "변화 1개")
            o.comparison.showsReorder = false
            #expect(o.comparison.summaryText == "변화 0개 · 순서 변경 1개 숨김")
            #expect(!o.comparison.hasNoChange)
            #expect(!o.comparison.isFilteredEmpty)
            o.comparison.changedOnly = true
            #expect(o.comparison.isFilteredEmpty)
            await o.comparison.setBefore(try await o.target(9))
            #expect(o.comparison.summaryText == "Board 이름 변경 · 순서 변경 1개 숨김")
            o.comparison.showsReorder = true
        }
    }

    @Test("[W19-decode-two-only] [W19-entry-read-failure] 고른 두 구성만 읽고, 읽지 못하면 안내하고 대상을 유지하거나 열지 않는다")
    func decodeFailures() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let damaged = try await o.revisionID(6)
            let staging = directory.appending(path: "browser/Fianchetto.store")
            _ = staging
            // 순번 6 스냅샷을 손상시킨다(이미 열린 저장소의 별도 문맥으로 고친다).
            let container = try StoreOpener.open(at: o.harness.url)
            let context = ModelContext(container)
            let model = try #require(try context.fetch(FetchDescriptor<SchemaV1.RevisionModel>()).first { $0.id == damaged })
            model.snapshotData = Data("{".utf8)
            try context.save()

            await o.model.selectInspectorTab(.history)
            await o.model.compareRecord(.revision(damaged))
            #expect(!o.model.isComparing)
            #expect(o.comparison.unreadableNotice)
            o.comparison.dismissNotice()

            await o.model.compareRecord(.revision(try await o.revisionID(3)))
            #expect(o.model.isComparing)
            await o.comparison.setBefore(.revision(damaged))
            #expect(o.comparison.unreadableNotice)
            #expect(o.comparison.before == (try await o.target(3)))
        }
    }

    @Test("[W19-stale-load-latest-wins] 늦게 끝난 대상 읽기 결과는 버리고 마지막 선택만 반영한다")
    func staleLoad() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let gate = LoadGate()
            let o = try await opened(directory, loadGate: gate)
            await o.model.selectInspectorTab(.history)
            await o.model.compareRecord(.revision(try await o.revisionID(3)))
            let five = try await o.revisionID(5), seven = try await o.revisionID(7)
            gate.hold(five)
            gate.hold(seven)
            let first = Task { await o.comparison.setBefore(.revision(five)) }
            await gate.waitUntilWaiting(five)
            let second = Task { await o.comparison.setBefore(.revision(seven)) }
            await gate.waitUntilWaiting(seven)
            #expect(o.comparison.before == (try await o.target(3)))
            gate.release(seven)
            await second.value
            gate.release(five)
            await first.value
            #expect(o.comparison.before == .revision(seven))
        }
    }

    enum Cancel: String, CaseIterable, Sendable { case currentRow, otherBoard, closeButton }

    @Test("[W19-load-cancelled] [W19-load-cancelled-open] 읽는 동안 비교를 닫거나 Board를 바꾸면 읽기가 끝나도 비교가 다시 열리지 않는다", arguments: Cancel.allCases)
    func cancelledLoad(cancel: Cancel) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let gate = LoadGate()
            let o = try await opened(directory, loadGate: gate)
            await o.model.selectInspectorTab(.history)
            let three = try await o.revisionID(3), five = try await o.revisionID(5)
            let task: Task<Void, Never>
            switch cancel {
            case .currentRow, .otherBoard:
                gate.hold(three)
                task = Task { await o.model.compareRecord(.revision(three)) }
                await gate.waitUntilWaiting(three)
                if cancel == .currentRow { await o.history.select(.current) } else { await o.model.select(o.other) }
                gate.release(three)
            case .closeButton:
                await o.model.compareRecord(.revision(three))
                gate.hold(five)
                task = Task { await o.comparison.setBefore(.revision(five)) }
                await gate.waitUntilWaiting(five)
                #expect(o.comparison.before == .revision(three))
                o.model.closeComparison()
                gate.release(five)
            }
            await task.value
            #expect(!o.model.isComparing)
            #expect(o.model.isSidebarVisible == (o.model.inspectorTab == .item))
        }
    }

    @Test("[W19-no-file-access] 비교는 파일 시스템에 접근하지 않고 연결 상태 확인도 하지 않는다")
    func noFileAccess() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = o.harness.bookmarks.scopedResolutions.count
            try await o.view(5)
            let afterView = o.harness.bookmarks.scopedResolutions.count
            await o.model.compareWithCurrent()
            o.comparison.selection = .row(try o.row(named: "backend").id)
            #expect(o.comparison.rows.isEmpty == false)
            #expect(o.harness.bookmarks.scopedResolutions.count == afterView)
            #expect(afterView == before)
            #expect(!o.model.canRefreshStatuses)
        }
    }

    @Test("[W19-archived-compare] 보관된 Board에서도 비교할 수 있다")
    func archived() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            try await o.view(5)
            await o.model.compareWithCurrent()
            #expect(o.model.isComparing)
            #expect(!o.comparison.rows.isEmpty)
        }
    }

    // MARK: 변화 표시

    @Test("[W19-change-labels] [W19-removed-row-style] [W19-board-rename-row] 변화 문구·제거 행·Board 이름 행", .tags(.A07))
    func changeLabels() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(5)
            await o.model.compareWithCurrent()
            let backend = try o.row(named: "backend"), notes = try o.row(named: "notes.md")
            #expect(o.comparison.changeText(backend) == "대상 교체")
            #expect(notes.isRemoved)
            #expect(o.comparison.changeText(notes) == "제거됨")
            #expect(o.model.comparisonAccessibilityLabel(notes) == "notes.md, Bishop, 제거됨")
            #expect(o.comparison.showsBoardNameRow)
            #expect(ComparisonModel.kindSymbol(.removed) == "minus.circle")
            #expect(ComparisonModel.kindSymbol(.targetReplaced) == "arrow.triangle.swap")
            #expect(o.comparison.summaryText == "변화 2개 · Board 이름 변경")
            // 제거 행은 이전 위치(개발 안, backend 뒤)에 있다.
            let dev = try o.row(named: "개발")
            #expect(dev.children.map(\.node.displayName) == ["backend", "notes.md"])
        }
    }

    @Test("[W19-moved-label-parent] [W19-multiple-kinds] 이동 문구는 이전 직접 부모 Wing 이름이고 여러 변화는 표 순서로 잇는다", .tags(.A07))
    func movedLabel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let backend = try #require(o.model.loadedSnapshot?.node(named: "backend")).id
            await o.model.requestMove(backend, toParent: nil, position: nil)
            o.model.selectedNodeID = backend
            o.model.beginRenameNode()
            o.model.nodeForm?.name = "api"
            await o.model.confirmNodeForm()
            try await o.view(10)
            await o.model.compareWithCurrent()
            #expect(o.comparison.changeText(try o.row(named: "api")) == "이름 변경 · ‘개발’에서 이동")
        }
    }

    @Test("[W19-changed-only-filter] [W19-changed-only-reset] '바뀐 항목만 보기'는 변화와 조상만 남기고 비교를 열 때마다 꺼진다")
    func changedOnly() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(8)
            await o.model.compareWithCurrent()
            o.comparison.changedOnly = true
            #expect(o.comparison.shownRows.map(\.node.displayName) == ["개발"])
            #expect(o.comparison.shownRows.first?.children.map(\.node.displayName) == ["notes.md"])
            o.model.closeComparison()
            await o.model.compareWithCurrent()
            #expect(!o.comparison.changedOnly)
        }
    }

    enum Detail: String, CaseIterable, Sendable { case target, removed, boardName, purposeAndName, moved }

    @Test("[W19-change-details] 고른 항목의 '변경 내용'은 바뀐 값만 '이전 → 이후'로 보인다", arguments: Detail.allCases)
    func changeDetails(detail: Detail) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            if detail == .purposeAndName || detail == .moved {
                let backend = try #require(o.model.loadedSnapshot?.node(named: "backend")).id
                if detail == .moved {
                    await o.model.requestMove(backend, toParent: nil, position: nil)
                } else {
                    o.model.selectedNodeID = backend
                    await o.model.setPurposeOfSelected(.code)
                    o.model.beginRenameNode()
                    o.model.nodeForm?.name = "api"
                    await o.model.confirmNodeForm()
                }
                try await o.view(10)
            } else {
                try await o.view(5)
            }
            await o.model.compareWithCurrent()
            let lines: [ComparisonModel.DetailLine]
            switch detail {
            case .target:
                o.comparison.selection = .row(try o.row(named: "backend").id)
                lines = o.comparison.detailLines
                #expect(lines.count == 1)
                #expect(lines.first?.label == "대상")
                #expect(lines.first?.text.contains(" → ") == true)
            case .removed:
                o.comparison.selection = .row(try o.row(named: "notes.md").id)
                lines = o.comparison.detailLines
                #expect(lines.first?.text == "제거됨")
                #expect(lines.contains(.init(label: "위치", text: "개발")))
            case .boardName:
                o.comparison.selection = .boardName
                #expect(o.comparison.detailLines == [.init(label: "이름", text: "서비스 A → 서비스 Alpha")])
            case .purposeAndName:
                o.comparison.selection = .row(try o.row(named: "api").id)
                #expect(o.comparison.detailLines == [.init(label: "이름", text: "backend → api"), .init(label: "아이콘", text: "기본 → 코드")])
            case .moved:
                o.comparison.selection = .row(try o.row(named: "backend").id)
                #expect(o.comparison.detailLines == [.init(label: "위치", text: "개발 → 최상위")])
            }
        }
    }

    @Test("[W19-inspector-tab-kept] 비교 행을 골라도 인스펙터 탭은 그대로다")
    func inspectorTabKept() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(5)
            await o.model.compareWithCurrent()
            o.comparison.selection = .row(try o.row(named: "backend").id)
            #expect(o.model.inspectorTab == .history)
        }
    }

    @Test("[W19-remembered-preferences] '순서 변경 표시'는 기본 켬이고 바꾸면 다시 실행해도 기억한다")
    func rememberedPreferences() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(o.comparison.showsReorder)
            o.comparison.showsReorder = false
            let relaunched = BrowserHarness(directory: o.harness.directory, lastBoard: o.harness.lastBoard)
            #expect(!relaunched.model.comparison.showsReorder)
        }
    }

    // MARK: 동작

    @Test("[W19-read-only] 비교 화면에서는 구성을 바꾸는 동작이 모두 꺼진다")
    func readOnly() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let backend = try #require(o.model.loadedSnapshot?.node(named: "backend")).id
            await o.model.selectNode(backend)
            await o.model.selectInspectorTab(.history)
            await o.model.compareRecord(.revision(try await o.revisionID(5)))
            let m = o.model
            #expect(!m.canAddToBoard)
            #expect(!m.canRenameSelectedNode)
            #expect(!m.canChangeURLOfSelected)
            #expect(!m.canMoveSelected && !m.canMoveSelectedUp && !m.canMoveSelectedDown)
            #expect(!m.canRemoveSelected)
            #expect(!m.canReplaceSelectedTarget)
            #expect(!m.canSetPurposeOfSelected)
            #expect(!m.canRenameSelectedBoard)
            #expect(!m.canAcceptDrop(on: nil))
            #expect(!m.canAcceptNodeDrop(backend, on: nil))
            m.beginRemove()
            #expect(m.removal == nil)
        }
    }

    enum MenuCase: String, CaseIterable, Sendable { case bishop, removed, webLink, wing, boardName, none }

    @Test("[W19-menu-commands-in-compare] [W19-open-by-row-reference] [W19-context-menu] 비교 중 메뉴 명령은 비교 행을 그 구성의 참조로 다룬다", arguments: MenuCase.allCases)
    func menuCommands(menu: MenuCase) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.selectNode(try #require(o.model.loadedSnapshot?.node(named: "API 명세")).id)
            try await o.view(5)
            await o.model.compareWithCurrent()
            switch menu {
            case .bishop: o.comparison.selection = .row(try o.row(named: "backend").id)
            case .removed: o.comparison.selection = .row(try o.row(named: "notes.md").id)
            case .webLink: o.comparison.selection = .row(try o.row(named: "API 명세").id)
            case .wing: o.comparison.selection = .row(try o.row(named: "개발").id)
            case .boardName: o.comparison.selection = .boardName
            case .none: o.comparison.selection = nil
            }
            let m = o.model
            #expect(!m.canReselectSelected && !m.canRefreshStatuses)
            #expect(!m.canEnterSelected && !m.canGoUp && !m.canGoBack && !m.canChangeViewMode)
            switch menu {
            case .bishop:
                #expect(m.canOpenSelected && m.canRevealSelected)
                await m.openSelected()
                #expect(canonical(o.harness.launcher.opened.last) == canonical(o.v2URL))
            case .removed:
                #expect(m.canOpenSelected && m.canRevealSelected)
                await m.revealSelected()
                #expect(o.harness.launcher.revealed.last?.lastPathComponent == "notes.md")
            case .webLink:
                #expect(m.canOpenSelected && !m.canRevealSelected)
                await m.openSelected()
                #expect(o.harness.launcher.opened.last?.absoluteString == "https://old.example.com")
            case .wing, .boardName, .none:
                #expect(!m.canOpenSelected && !m.canRevealSelected)
                await m.openSelected()
                #expect(o.harness.launcher.opened.isEmpty)
            }
        }
    }

    @Test("[W19-return-to-current-closes] 과거 구성에서 연 비교에서 '현재 구성으로 돌아가기'는 비교를 닫고 현재 구성을 보인다")
    func returnToCurrentCloses() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(5)
            await o.model.compareWithCurrent()
            await o.model.returnToCurrent()
            #expect(!o.model.isComparing)
            #expect(!o.model.isViewingPast)
            #expect(o.history.selection == .current)
        }
    }

    enum Closing: String, CaseIterable, Sendable { case fromPast, fromCurrent, fromIconWing }

    @Test("[W19-close-returns] [W19-icon-view-list] 비교를 닫으면 열기 전 화면(과거·현재, 아이콘 보기 위치)으로 돌아간다", arguments: Closing.allCases)
    func closeReturns(closing: Closing) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            switch closing {
            case .fromPast:
                try await o.view(5)
                await o.model.compareWithCurrent()
                o.model.closeComparison()
                #expect(o.model.isViewingPast)
                #expect(o.history.selectedSummary?.sequence == 5)
            case .fromCurrent:
                await o.model.selectInspectorTab(.history)
                await o.model.compareRecord(.revision(try await o.revisionID(5)))
                o.model.closeComparison()
                #expect(!o.model.isViewingPast)
            case .fromIconWing:
                o.model.showIcons()
                let dev = try #require(o.model.loadedSnapshot?.node(named: "개발")).id
                await o.model.activateTile(dev)
                await o.model.selectInspectorTab(.history)
                await o.model.compareRecord(.revision(try await o.revisionID(5)))
                #expect(o.model.viewMode == .icons)
                o.model.closeComparison()
                #expect(o.model.viewMode == .icons)
                #expect(o.model.iconLocationID == dev)
                #expect(o.model.canGoBack)
            }
            #expect(!o.model.isComparing)
        }
    }

    @Test("[W19-separate-selection] 비교 중 고른 항목은 원래 선택과 따로 두고 닫으면 원래 선택으로 돌아간다")
    func separateSelection() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let api = try #require(o.model.loadedSnapshot?.node(named: "API 명세")).id
            await o.model.selectNode(api)
            await o.model.selectInspectorTab(.history)
            await o.model.compareRecord(.revision(try await o.revisionID(5)))
            o.comparison.selection = .row(try o.row(named: "backend").id)
            o.model.closeComparison()
            #expect(o.model.selectedNodeID == api)
            #expect(o.model.inspector?.displayName == "API 명세")
            #expect(o.comparison.selection == nil)
        }
    }

    @Test("[W19-history-row-closes] 비교 중 이력 행이나 '현재 구성' 행을 고르면 비교를 닫고 그 구성을 본다")
    func historyRowCloses() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.view(3)
            await o.model.compareWithCurrent()
            try await o.view(5)
            #expect(!o.model.isComparing)
            #expect(o.history.selectedSummary?.sequence == 5)
            await o.model.compareWithCurrent()
            await o.history.select(.current)
            #expect(!o.model.isComparing)
            #expect(!o.model.isViewingPast)
        }
    }

    enum Sidebar: String, CaseIterable, Sendable { case openOnly, openClose, historyClosedFirst, bothClosed, hiddenStart }

    @Test("[W19-sidebar-collapse] 비교 중에는 사이드바를 접고 자동으로 접는 화면이 모두 닫힐 때 처음 상태로 돌린다", arguments: Sidebar.allCases)
    func sidebar(sidebar: Sidebar) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let five = try await o.revisionID(5)
            if sidebar == .hiddenStart { o.model.isSidebarVisible = false }
            switch sidebar {
            case .openOnly:
                await o.model.compareRecord(.revision(five))
                #expect(!o.model.isSidebarVisible)
            case .openClose, .hiddenStart:
                await o.model.compareRecord(.revision(five))
                o.model.closeComparison()
                #expect(o.model.isSidebarVisible == (sidebar == .openClose))
            case .historyClosedFirst:
                await o.model.selectInspectorTab(.history)
                await o.model.compareRecord(.revision(five))
                await o.model.selectInspectorTab(.item)
                #expect(!o.model.isSidebarVisible)
            case .bothClosed:
                await o.model.selectInspectorTab(.history)
                await o.model.compareRecord(.revision(five))
                o.model.closeComparison()
                #expect(!o.model.isSidebarVisible)
                await o.model.selectInspectorTab(.item)
                #expect(o.model.isSidebarVisible)
            }
        }
    }

    @Test("[W19-board-switch-closes] 다른 Board를 고르면 비교가 닫힌다")
    func boardSwitch() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.compareRecord(.revision(try await o.revisionID(5)))
            await o.model.select(o.other)
            #expect(!o.model.isComparing)
            #expect(o.model.shownSnapshot?.projectName == "서비스 B")
        }
    }

    @Test("[W19-browse-no-revision] 비교를 열고 대상·'순서 변경 표시'를 바꾸고 닫아도 revision과 현재 구성은 그대로다")
    func browseNoRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let current = try await o.store.project(o.project)?.currentRevisionID
            await o.model.compareRecord(.revision(try await o.revisionID(5)))
            await o.comparison.setBefore(try await o.target(3))
            o.comparison.showsReorder = false
            o.comparison.selection = .row(try o.row(named: "backend").id)
            o.model.closeComparison()
            #expect(try await o.revisionCount() == 10)
            #expect(try await o.store.project(o.project)?.currentRevisionID == current)
        }
    }
}
