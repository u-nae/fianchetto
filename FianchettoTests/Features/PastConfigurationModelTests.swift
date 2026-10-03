import Foundation
import Testing
@testable import Fianchetto

/// 과거 구성 읽기 전용 보기와 당시 대상 열기(W18).
@MainActor
@Suite("과거 구성 보기(W18)")
struct PastConfigurationModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let other: UUID
        let legacyURL: URL
        let v2URL: URL
        let directory: URL
        var model: BoardBrowserModel { harness.model }
        var history: HistoryPanelModel { harness.model.history }
        var store: ProjectStore { model.openedStore!.store }
        var bookmarks: ScriptedBookmarkSystem { harness.bookmarks }
        var launcher: RecordingLauncher { harness.launcher }

        func id(_ name: String) throws -> UUID {
            try #require(model.shownSnapshot?.node(named: name)).id
        }

        var shownNames: Set<String> { Set(model.shownSnapshot?.nodes.map(\.displayName) ?? []) }

        func revisionID(_ sequence: Int) async throws -> UUID {
            try #require(try await store.revisionSummaries(projectID: project).first { $0.sequence == sequence }).id
        }

        func revisionCount() async throws -> Int {
            try await store.revisionSummaries(projectID: project).count
        }

        func currentRevisionID() async throws -> UUID? {
            try await store.project(project)?.currentRevisionID
        }

        /// 순번 5(과거 구성)를 고른다.
        func viewPast() async throws {
            await model.selectInspectorTab(.history)
            await history.select(.revision(try await revisionID(5)))
        }
    }

    static let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
    static let noEvidence = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)

    /// "서비스 A" revision:
    /// 1 Board 만들기, 2 Bishop 폴더 backend(legacy) 추가, 3 Wing 개발, 4 웹 링크 "API 명세"(old URL), 5 backend 용도 code,
    /// 6 backend 대상 → v2, 7 URL → new, 8 용도 data, 9 Wing 문서. 현재 revision은 9. 다른 Board "서비스 B"가 있다.
    private func opened(_ directory: URL, archived: Bool = false, clock: HistoryClock = HistoryClock()) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"), clock: clock)
        let legacy = try TargetFiles.folder(directory, "targets/legacy/backend")
        let v2 = try TargetFiles.folder(directory, "targets/v2/backend")
        var ids = (UUID(), UUID())
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [legacy]))
            let backend = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "backend")).id
            _ = try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board)
            _ = try await seed.service.apply(.addWebLink(name: "API 명세", url: "https://old.example.com", parentID: nil, position: nil), to: board)
            let link = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "API 명세")).id
            _ = try await seed.service.apply(.changePurpose(backend, "code"), to: board)
            let replacement = TargetReplacementService(bookmarks: BookmarkAdapter(system: seed.bookmarks), configuration: seed.service)
            let preview = try await replacement.preview(projectID: board, nodeID: backend, newURL: v2).get()
            _ = try await replacement.confirm(preview)
            _ = try await seed.service.apply(.changeURL(link, "https://new.example.com"), to: board)
            _ = try await seed.service.apply(.changePurpose(backend, "data"), to: board)
            _ = try await seed.service.apply(.addGroup(name: "문서", parentID: nil, position: nil), to: board)
            let other = try await makeBoard(seed, "서비스 B")
            if archived { try await seed.store.setArchived(board, at: date(100)) }
            ids = (board, other)
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, project: ids.0, other: ids.1, legacyURL: legacy, v2URL: v2, directory: directory)
    }

    private func canonical(_ path: String) -> String {
        URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func canonical(_ url: URL?) -> String? {
        url.map { canonical($0.path) }
    }

    // MARK: 과거 구성 보기

    @Test("[W18-past-view] revision을 고르면 가운데 영역이 그 revision 구성으로 바뀌고 과거 구성 띠가 붙는다", .tags(.A06))
    func pastView() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(!o.model.isViewingPast)
            #expect(o.shownNames == ["backend", "개발", "API 명세", "문서"])
            try await o.viewPast()
            #expect(o.model.isViewingPast)
            #expect(o.shownNames == ["backend", "개발", "API 명세"])
            #expect(Set(o.model.tree.map(\.node.displayName)) == ["backend", "개발", "API 명세"])
            #expect(o.model.pastBannerTitle == "과거 구성 · 읽기 전용")
            let summary = try #require(o.history.selectedSummary)
            #expect(summary.sequence == 5)
            let expected = Self.koreanDateTime(summary.recordedAt, zone: "Asia/Seoul")
            #expect(o.model.pastBannerDetail == "#5 · \(expected) 기록")
            #expect(o.model.pastBannerAccessibilityLabel == "과거 구성, 읽기 전용, #5, \(expected) 기록")
            // 현재 구성 값 자체는 그대로다.
            #expect(o.model.loadedSnapshot?.node(named: "문서") != nil)
        }
    }

    /// 예: "2026년 10월 3일 오후 2:20".
    static func koreanDateTime(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "y년 M월 d일 a h:mm"
        return formatter.string(from: date)
    }

    @Test("[W18-past-view] 띠의 기록 시각은 시스템 시간대를 따른다")
    func bannerTimeZone() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let clock = HistoryClock()
            let o = try await opened(directory, clock: clock)
            try await o.viewPast()
            let recorded = try #require(o.history.selectedSummary).recordedAt
            #expect(o.model.pastBannerDetail == "#5 · \(Self.koreanDateTime(recorded, zone: "Asia/Seoul")) 기록")
            clock.zone = "America/Los_Angeles"
            o.history.clockChanged()
            #expect(o.model.pastBannerDetail == "#5 · \(Self.koreanDateTime(recorded, zone: "America/Los_Angeles")) 기록")
            #expect(Self.koreanDateTime(recorded, zone: "Asia/Seoul") != Self.koreanDateTime(recorded, zone: "America/Los_Angeles"))
        }
    }

    @Test("[W18-icon-view-past] 아이콘 보기에서도 같은 과거 구성을 보이고 Wing 탐색은 그대로 쓴다")
    func iconViewPast() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            try await o.viewPast()
            #expect(Set(o.model.iconItems.map(\.displayName)) == ["backend", "개발", "API 명세"])
            await o.model.activateTile(try o.id("개발"))
            #expect(o.model.iconItems.isEmpty)
            o.model.goUp()
            #expect(o.model.isViewingPast)
            #expect(Set(o.model.iconItems.map(\.displayName)) == ["backend", "개발", "API 명세"])
        }
    }

    @Test("[W18-icon-path-trim] 아이콘 보기 위치의 Wing이 고른 revision에 없으면 최상위를 보인다")
    func iconPathTrim() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            await o.model.activateTile(try o.id("문서"))
            #expect(o.model.iconLocationID == (try o.id("문서")))
            try await o.viewPast()
            #expect(o.model.iconLocationID == nil)
            #expect(Set(o.model.iconItems.map(\.displayName)) == ["backend", "개발", "API 명세"])
        }
    }

    enum Return: String, CaseIterable, Sendable { case banner, currentRow, menu }

    @Test("[W18-return-to-current] 띠·현재 구성 행·보기 메뉴로 현재 구성에 돌아간다", arguments: Return.allCases)
    func returnToCurrent(way: Return) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            #expect(o.model.canReturnToCurrent)
            switch way {
            case .banner, .menu: await o.model.returnToCurrent()
            case .currentRow: await o.history.select(.current)
            }
            #expect(!o.model.isViewingPast)
            #expect(o.shownNames == ["backend", "개발", "API 명세", "문서"])
            #expect(o.history.selection == .current)
            #expect(o.model.pastBannerDetail == nil)
        }
    }

    @Test("[W18-return-disabled] 과거 구성을 보지 않으면 현재 구성으로 돌아가기가 꺼진다")
    func returnDisabled() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(!o.model.canReturnToCurrent)
            await o.model.returnToCurrent()
            #expect(!o.model.isViewingPast)
        }
    }

    @Test("[W18-tab-close-keeps-past] 이력 탭을 닫아도 과거 구성 보기와 띠가 이어진다")
    func tabCloseKeepsPast() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectInspectorTab(.item)
            #expect(o.model.isViewingPast)
            #expect(o.model.pastBannerDetail?.hasPrefix("#5 · ") == true)
            #expect(!o.shownNames.contains("문서"))
        }
    }

    @Test("[W18-board-switch] 다른 Board를 고르면 그 Board의 현재 구성으로 돌아간다")
    func boardSwitch() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.select(o.other)
            #expect(!o.model.isViewingPast)
            #expect(o.model.shownSnapshot?.projectName == "서비스 B")
        }
    }

    @Test("[W18-relaunch] 다시 실행하면 현재 구성으로 시작한다")
    func relaunch() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            let relaunched = BrowserHarness(directory: o.harness.directory, lastBoard: o.harness.lastBoard)
            await relaunched.model.start()
            #expect(!relaunched.model.isViewingPast)
            #expect(relaunched.model.shownSnapshot?.node(named: "문서") != nil)
        }
    }

    enum Crossing: String, CaseIterable, Sendable { case keptIntoPast, droppedIntoPast, keptIntoCurrent }

    @Test("[W18-selection-across-modes] 과거·현재를 오갈 때 고른 항목은 보이는 구성에 있으면 남고 없으면 비워진다", arguments: Crossing.allCases)
    func selectionAcrossModes(crossing: Crossing) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            switch crossing {
            case .keptIntoPast:
                let backend = try o.id("backend")
                await o.model.selectNode(backend)
                try await o.viewPast()
                #expect(o.model.selectedNodeID == backend)
            case .droppedIntoPast:
                await o.model.selectNode(try o.id("문서"))
                try await o.viewPast()
                #expect(o.model.selectedNodeID == nil)
            case .keptIntoCurrent:
                try await o.viewPast()
                let wing = try o.id("개발")
                await o.model.selectNode(wing)
                await o.model.returnToCurrent()
                #expect(o.model.selectedNodeID == wing)
            }
        }
    }

    // MARK: 읽기 전용

    @Test("[W18-read-only] 과거 구성에서는 구성을 바꾸는 동작이 모두 꺼진다", .tags(.A06))
    func readOnly() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            let backend = try o.id("backend"), wing = try o.id("개발")
            await o.model.selectNode(backend)
            let m = o.model
            #expect(!m.canAddToBoard)
            #expect(!m.canRenameSelectedNode)
            #expect(!m.canChangeURLOfSelected)
            #expect(!m.canMoveSelected)
            #expect(!m.canMoveSelectedUp)
            #expect(!m.canMoveSelectedDown)
            #expect(!m.canRemoveSelected)
            #expect(!m.canReplaceSelectedTarget)
            #expect(!m.canSetPurposeOfSelected)
            #expect(!m.canRenameSelectedBoard)
            #expect(!m.canAcceptNodeDrop(backend, on: wing))
            #expect(!m.canAcceptDrop(on: nil))
            #expect(!m.canAcceptIconFileDrop(onTile: nil))
            m.beginRemove()
            #expect(m.removal == nil)
            #expect(m.linkNotice == nil)
            // 열기·Finder에서 보기·다시 선택은 남는다(16.4).
            #expect(m.canOpenSelected)
            #expect(m.canRevealSelected)
            #expect(m.canReselectSelected)
        }
    }

    @Test("[W18-no-edit-revision] 과거 구성에서 끌어다 놓기·이름 변경·Finder 드롭을 시도해도 revision이 생기지 않는다")
    func noEditRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            let before = try await o.revisionCount()
            let backend = try o.id("backend"), wing = try o.id("개발")
            #expect(await o.model.dropNode(backend, on: wing) == false)
            await o.model.selectNode(backend)
            o.model.beginRenameNode()
            #expect(o.model.nodeForm == nil)
            await o.model.requestMove(backend, toParent: wing, position: nil)
            #expect(await o.model.dropFilesInIconView([o.v2URL], onTile: nil) == false)
            #expect(try await o.revisionCount() == before)
            #expect(try await o.currentRevisionID() == (try await o.revisionID(9)))
        }
    }

    @Test("[W18-past-purpose] 과거 구성의 용도 배지는 당시 값이고 세 고르는 곳의 조건이 꺼진다")
    func pastPurpose() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(o.model.shownSnapshot?.node(named: "backend")?.knownPurpose == .data)
            try await o.viewPast()
            await o.model.selectNode(try o.id("backend"))
            #expect(o.model.shownSnapshot?.node(named: "backend")?.knownPurpose == .code)
            #expect(o.model.selectedPurpose == .code)
            #expect(o.model.inspector?.purpose == "코드")
            #expect(!o.model.canSetPurposeOfSelected)
            await o.model.setPurposeOfSelected(.design)
            #expect(try await o.revisionCount() == 9)
        }
    }

    @Test("[W18-context-menu] 과거 구성의 Wing은 목록 보기에서 편집 동작이 없고 아이콘 보기에서는 들어갈 수 있다")
    func contextCapabilities() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("개발"))
            #expect(!o.model.canOpenSelected)
            #expect(!o.model.canReselectSelected)
            #expect(!o.model.canRenameSelectedNode)
            #expect(!o.model.canAddToBoard)
            o.model.showIcons()
            await o.model.activateTile(try o.id("개발"))
            #expect(o.model.iconLocationID == (try o.id("개발")))
        }
    }

    // MARK: 과거 항목 열기와 위치

    @Test("[W18-open-past-reference] 대상 교체 뒤 과거 항목은 그 revision의 reference가 지금 해석하는 대상을 연다", .tags(.A06))
    func openPastReference() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("backend"))
            await o.model.openSelected()
            #expect(canonical(o.launcher.opened.last) == canonical(o.legacyURL.path))
            await o.model.returnToCurrent()
            await o.model.open(try o.id("backend"))
            #expect(canonical(o.launcher.opened.last) == canonical(o.v2URL.path))
            #expect(o.launcher.opened.count == 2)
        }
    }

    @Test("[W18-reveal-past-reference] 과거 항목 Finder에서 보기도 그 revision의 reference로 한다", .tags(.A06))
    func revealPastReference() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("backend"))
            await o.model.revealSelected()
            #expect(o.launcher.revealed.map { canonical($0.path) } == [canonical(o.legacyURL.path)])
        }
    }

    enum Location: String, CaseIterable, Sendable { case same, moved, denied, deleted }

    @Test("[W18-location-card] 고른 항목 카드는 당시 경로와 현재 위치(또는 상태)를 보이고 경로가 다를 때만 알린다", .tags(.A06), arguments: Location.allCases)
    func locationCard(location: Location) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            var movedURL: URL?
            switch location {
            case .same: break
            case .moved:
                let target = directory.appending(path: "archive/backend")
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: o.legacyURL, to: target)
                movedURL = target
            case .denied: o.bookmarks.failResolution(with: Self.denied, scopedOnly: true)
            case .deleted: try FileManager.default.removeItem(at: o.legacyURL)
            }
            try await o.viewPast()
            await o.model.selectNode(try o.id("backend"))
            let card = try #require(o.model.pastItemCard)
            #expect(card.name == "backend")
            #expect(card.kind == .folder)
            #expect(card.recordedPath.map(canonical) == canonical(o.legacyURL.path))
            switch location {
            case .same:
                guard case let .resolved(path, differs)? = card.location else { Issue.record("위치 없음"); return }
                #expect(canonical(path) == canonical(o.legacyURL.path))
                #expect(!differs)
            case .moved:
                guard case let .resolved(path, differs)? = card.location else { Issue.record("위치 없음"); return }
                let moved = try #require(movedURL)
                #expect(canonical(path) == canonical(moved.path))
                #expect(differs)
            case .denied:
                #expect(card.location == .unresolved(.accessRequired))
            case .deleted:
                #expect(card.location == .unresolved(.missing))
            }
            #expect(o.model.movedLocationText == "당시와 다른 위치")
        }
    }

    @Test("[W18-current-content-notice] 카드는 지금의 파일이 열린다는 안내를 둔다", .tags(.A06))
    func currentContentNotice() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("backend"))
            #expect(o.model.pastItemCard != nil)
            #expect(o.model.currentContentNotice == "열면 지금의 파일이 열립니다. 파일 내용의 과거 버전은 보관하지 않습니다.")
            #expect(o.model.canOpenSelected && o.model.canRevealSelected)
        }
    }

    @Test("[W18-web-link-card] 웹 링크 카드는 당시 URL을 보이고 열기는 당시 URL을 연다")
    func webLinkCard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("API 명세"))
            let card = try #require(o.model.pastItemCard)
            #expect(card.url == "https://old.example.com")
            #expect(card.recordedPath == nil)
            await o.model.openSelected()
            #expect(o.launcher.opened.last?.absoluteString == "https://old.example.com")
        }
    }

    @Test("[W18-wing-card] Wing 카드는 이름만 있다")
    func wingCard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("개발"))
            let card = try #require(o.model.pastItemCard)
            #expect(card == .init(name: "개발", kind: .group, recordedPath: nil, location: nil, url: nil))
        }
    }

    @Test("[W18-no-card-without-selection] 과거 구성에서 항목을 고르지 않았으면 카드가 없다")
    func noCardWithoutSelection() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            #expect(o.model.selectedNodeID == nil)
            #expect(o.model.pastItemCard == nil)
        }
    }

    @Test("[W18-no-card-in-current] 현재 구성을 볼 때는 카드가 없다")
    func noCardInCurrent() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            await o.model.selectNode(try o.id("backend"))
            await o.model.selectInspectorTab(.history)
            #expect(o.model.pastItemCard == nil)
        }
    }

    @Test("[W18-open-failure] 과거 항목을 열지 못하면 기존 열기 실패 안내를 보이고 기록하지 않는다")
    func openFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("backend"))
            o.bookmarks.failResolution(with: Self.noEvidence, volumeUnmounted: true)
            await o.model.openSelected()
            #expect(o.model.linkNotice?.kind == .openFailed(.unreachable(.volumeUnavailable)))
            #expect(o.launcher.opened.isEmpty)
            #expect(try await o.revisionCount() == 9)
        }
    }

    @Test("[W18-status-separate] 과거 항목 상태는 그 revision의 reference로 확인하고 현재 구성 상태와 섞지 않는다")
    func statusSeparate() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.legacyURL)
            let backend = try o.id("backend")
            await o.model.selectNode(backend)
            #expect(o.model.linkStatuses[backend] == .healthy)
            try await o.viewPast()
            #expect(o.model.displayedStatus(of: backend) == .missing)
            await o.model.returnToCurrent()
            #expect(o.model.linkStatuses[backend] == .healthy)
            #expect(o.model.displayedStatus(of: backend) == nil)
        }
    }

    @Test("[W18-status-separate] 현재 구성에서 확인한 다른 항목의 상태가 과거 구성에 남지 않는다")
    func currentStatusDoesNotLeak() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.v2URL)
            let backend = try o.id("backend")
            await o.model.refreshStatuses()
            #expect(o.model.displayedStatus(of: backend) == .missing)
            try await o.viewPast()
            #expect(o.model.selectedNodeID == nil)
            #expect(o.model.displayedStatus(of: backend) == nil)
        }
    }

    @Test("[W18-status-separate] 과거 모드의 상태 새로고침은 보이는 과거 구성의 참조로 확인한다")
    func refreshInPast() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.legacyURL)
            try await o.viewPast()
            await o.model.refreshStatuses()
            #expect(o.model.displayedStatus(of: try o.id("backend")) == .missing)
        }
    }

    @Test("[W18-refresh-access-only] 과거 항목 해석 중 새 접근 정보는 참조만 갱신하고 revision과 당시 경로는 그대로다")
    func refreshAccessOnly() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            let node = try #require(o.model.shownSnapshot?.node(named: "backend"))
            let referenceID = try #require(node.referenceID)
            let original = try #require(try await o.store.reference(referenceID))
            let moved = directory.appending(path: "moved/backend")
            try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: o.legacyURL, to: moved)

            await o.model.selectNode(node.id)
            await o.model.openSelected()
            let updated = try #require(try await o.store.reference(referenceID))
            #expect(updated.bookmarkData != original.bookmarkData)
            #expect(updated.lastResolvedPath.map(canonical) == canonical(moved.path))
            #expect(try await o.revisionCount() == 9)
            let past = try await o.store.snapshot(revisionID: try await o.revisionID(5))
            #expect(past.node(named: "backend")?.recordedPath == node.recordedPath)
        }
    }

    // MARK: 과거 화면의 다시 선택

    @Test("[W18-reselect-same] 과거 화면 다시 선택이 같은 대상이면 접근만 복구하고 revision·참조는 그대로다")
    func reselectSame() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            let node = try #require(o.model.shownSnapshot?.node(named: "backend"))
            let referenceID = try #require(node.referenceID)
            let original = try #require(try await o.store.reference(referenceID))
            o.bookmarks.failResolution(with: Self.denied, scopedOnly: true)
            await o.model.selectNode(node.id)
            #expect(o.model.displayedStatus(of: node.id) == .accessRequired)

            // 같은 대상을 옮긴 위치에서 고른다(같은 파일 시스템 식별자). 접근 정보가 그 위치로 갱신된다.
            o.bookmarks.clearResolutionFailure()
            let moved = directory.appending(path: "moved/backend")
            try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: o.legacyURL, to: moved)
            o.harness.picker.replacementResults = [moved]
            await o.model.reselectSelectedTarget()
            #expect(o.model.replacement == nil)
            #expect(o.model.linkNotice == nil)
            #expect(o.model.linkStatuses[node.id] == .healthy)
            let updated = try #require(try await o.store.reference(original.id))
            #expect(updated.bookmarkData != original.bookmarkData)
            #expect(updated.lastResolvedPath.map(canonical) == canonical(moved.path))
            #expect(try await o.revisionCount() == 9)
            let past = try await o.store.snapshot(revisionID: try await o.revisionID(5))
            #expect(past.node(named: "backend")?.referenceID == node.referenceID)
        }
    }

    enum Other: String, CaseIterable, Sendable { case differentTarget, undetermined }

    @Test("[W18-reselect-other-rejected] 과거 화면 다시 선택이 다른 대상·판정 불가면 확인 창 없이 안내하고 아무것도 바꾸지 않는다", arguments: Other.allCases)
    func reselectOtherRejected(other: Other) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            let node = try #require(o.model.shownSnapshot?.node(named: "backend"))
            let referenceID = try #require(node.referenceID)
            let original = try #require(try await o.store.reference(referenceID))
            await o.model.selectNode(node.id)
            switch other {
            case .differentTarget:
                o.harness.picker.replacementResults = [o.v2URL]
            case .undetermined:
                // 기존 대상을 어떤 방식으로도 해석하지 못하면 식별자가 없어 판정할 수 없다(0012).
                o.bookmarks.failResolution(with: Self.noEvidence)
                o.harness.picker.replacementResults = [o.legacyURL]
            }
            await o.model.reselectSelectedTarget()
            #expect(o.model.replacement == nil)
            #expect(o.model.linkNotice?.kind == .pastSameTargetOnly)
            #expect(o.model.noticeText(try #require(o.model.linkNotice)) == "과거 구성에서는 같은 대상의 접근만 복구할 수 있습니다.")
            #expect(try await o.store.reference(original.id) == original)
            #expect(try await o.revisionCount() == 9)
            #expect(o.model.loadedSnapshot?.node(named: "backend")?.referenceID != node.referenceID)
        }
    }

    @Test("[W18-reselect-kind-mismatch] 과거 화면 다시 선택에서 종류가 다르면 기존 종류 불일치 안내를 보이고 바꾸지 않는다")
    func reselectKindMismatch() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let file = try TargetFiles.file(directory, "targets/readme.md")
            try await o.viewPast()
            let node = try #require(o.model.shownSnapshot?.node(named: "backend"))
            let referenceID = try #require(node.referenceID)
            let original = try #require(try await o.store.reference(referenceID))
            await o.model.selectNode(node.id)
            o.harness.picker.replacementResults = [file]
            await o.model.reselectSelectedTarget()
            #expect(o.model.linkNotice?.kind == .changeFailed)
            #expect(try await o.store.reference(original.id) == original)
            #expect(try await o.revisionCount() == 9)
        }
    }

    @Test("[W18-reselect-same] 과거 화면 다시 선택을 취소하면 아무것도 바꾸지 않는다")
    func reselectCancel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("backend"))
            o.harness.picker.replacementResults = [nil]
            await o.model.reselectSelectedTarget()
            #expect(o.model.linkNotice == nil)
            #expect(o.model.replacement == nil)
            #expect(try await o.revisionCount() == 9)
        }
    }

    @Test("[W18-reselect-same] 과거 화면 다시 선택의 접근 정보 저장이 실패하면 저장 실패를 안내한다")
    func reselectSaveFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            let node = try #require(o.model.shownSnapshot?.node(named: "backend"))
            let referenceID = try #require(node.referenceID)
            let original = try #require(try await o.store.reference(referenceID))
            await o.model.selectNode(node.id)
            o.harness.picker.replacementResults = [o.legacyURL]
            o.harness.fault.failNext()
            await o.model.reselectSelectedTarget()
            #expect(o.model.linkNotice?.kind == .saveFailed)
            #expect(try await o.store.reference(original.id) == original)
        }
    }

    @Test("[W18-archived-reselect] 보관된 Board의 과거 화면도 같은 대상은 복구하고 다른 대상은 과거 구성 안내를 보인다")
    func archivedReselect() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            try await o.viewPast()
            let node = try #require(o.model.shownSnapshot?.node(named: "backend"))
            let referenceID = try #require(node.referenceID)
            let original = try #require(try await o.store.reference(referenceID))
            await o.model.selectNode(node.id)
            let moved = directory.appending(path: "moved/backend")
            try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: o.legacyURL, to: moved)
            o.harness.picker.replacementResults = [o.v2URL, moved]
            await o.model.reselectSelectedTarget()
            #expect(o.model.linkNotice?.kind == .pastSameTargetOnly)
            o.model.dismissLinkNotice()
            await o.model.reselectSelectedTarget()
            #expect(o.model.linkNotice == nil)
            let recovered = try #require(try await o.store.reference(original.id))
            #expect(recovered.lastResolvedPath.map(canonical) == canonical(moved.path))
            #expect(try await o.revisionCount() == 9)
        }
    }

    // MARK: 기록하지 않음

    @Test("[W18-browse-no-revision] 과거 보기·고르기·열기·돌아가기는 revision을 만들지 않는다", .tags(.A06))
    func browsingRecordsNothing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try await o.viewPast()
            await o.model.selectNode(try o.id("backend"))
            await o.model.openSelected()
            await o.model.returnToCurrent()
            #expect(try await o.revisionCount() == 9)
            #expect(try await o.currentRevisionID() == (try await o.revisionID(9)))
        }
    }
}
