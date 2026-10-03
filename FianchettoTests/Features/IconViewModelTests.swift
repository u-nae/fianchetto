import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("아이콘 보기와 Wing 단위 탐색 (W28)")
struct IconViewModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let lastBoard: InMemoryLastBoard
        let project: UUID
        let other: UUID
        let directory: URL
        let readmeURL: URL
        var model: BoardBrowserModel { harness.model }

        func id(_ name: String) throws -> UUID {
            try #require(model.loadedSnapshot?.node(named: name)).id
        }

        func revisions() async throws -> Int {
            try await model.openedStore!.store.revisionSummaries(projectID: project).count
        }

        var tileNames: [String] { model.iconItems.map(\.displayName) }
    }

    /// "서비스 A" 최상위: Wing "개발"(0), Bishop 파일 "README.md"(1), 웹 링크 "API 명세"(2).
    /// "개발" 안: Bishop 폴더 "backend"(0), Wing "하위"(1). "하위" 안: Bishop 파일 "설계.key". 다른 Board "디자인 시스템".
    private func opened(
        _ directory: URL, archived: Bool = false, emptyWing: Bool = false, lastBoard: InMemoryLastBoard = InMemoryLastBoard()
    ) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"), lastBoard: lastBoard)
        let readme = try TargetFiles.file(directory, "targets/README.md", contents: "readme")
        let backend = try TargetFiles.folder(directory, "targets/backend")
        let design = try TargetFiles.file(directory, "targets/설계.key", contents: "key")
        var ids = (UUID(), UUID())
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            func add(_ edit: ConfigurationEdit) async throws -> ConfigurationSnapshot {
                try #require(try await seed.service.apply(edit, to: board).committed).snapshot
            }
            let dev = try #require(try await add(.addGroup(name: "개발", parentID: nil, position: nil)).node(named: "개발")).id
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [readme]))
            _ = try await add(.addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil))
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: dev, position: nil, urls: [backend]))
            let sub = try #require(try await add(.addGroup(name: "하위", parentID: dev, position: nil)).node(named: "하위")).id
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: sub, position: nil, urls: [design]))
            if emptyWing { _ = try await add(.addGroup(name: "보관", parentID: dev, position: nil)) }
            let other = try await makeBoard(seed, "디자인 시스템")
            if archived { try await seed.store.setArchived(board, at: date(100)) }
            ids = (board, other)
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, lastBoard: lastBoard, project: ids.0, other: ids.1, directory: directory, readmeURL: readme)
    }

    // MARK: 전환과 기억

    @Test("[W28-view-mode-per-board] 보기 방식은 처음 목록이고 Board마다 따로, 다시 실행해도 기억한다")
    func viewModePerBoard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(o.model.viewMode == .list)
            let before = try await o.revisions()

            o.model.showIcons()
            await o.model.select(o.other)
            #expect(o.model.viewMode == .list)

            let relaunched = BrowserHarness(directory: directory.appending(path: "browser"), lastBoard: o.lastBoard)
            await relaunched.model.start()
            await relaunched.model.select(o.project)
            #expect(relaunched.model.viewMode == .icons)
            #expect(relaunched.model.iconLocationID == nil)
            #expect(try await o.revisions() == before)
        }
    }

    enum StartCase: String, CaseIterable, Sendable { case freshNoSelection, freshBackend, freshDesign, sessionNoSelection, sessionWebLink }

    @Test("[W28-switch-location] 아이콘 보기로 바꾸면 선택의 부모, 없으면 이번 세션 위치, 그것도 없으면 최상위에서 시작한다", arguments: StartCase.allCases)
    func switchLocation(start: StartCase) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            if start == .sessionNoSelection || start == .sessionWebLink {
                o.model.showIcons()
                o.model.enter(try o.id("개발"))
                o.model.enter(try o.id("하위"))
                o.model.showList()
            }
            let selected: UUID? = switch start {
            case .freshNoSelection, .sessionNoSelection: nil
            case .freshBackend: try o.id("backend")
            case .freshDesign: try o.id("설계.key")
            case .sessionWebLink: try o.id("API 명세")
            }
            o.model.selectedNodeID = selected

            o.model.showIcons()

            let expected: UUID? = switch start {
            case .freshNoSelection, .sessionWebLink: nil
            case .freshBackend: try o.id("개발")
            case .freshDesign, .sessionNoSelection: try o.id("하위")
            }
            #expect(o.model.iconLocationID == expected)
            #expect(o.model.selectedNodeID == selected)
        }
    }

    @Test("[W28-one-level-in-order] 아이콘 보기는 현재 위치 한 단계만 구성 순서대로 보이고 경로와 항목 수를 보인다")
    func oneLevelInOrder() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            #expect(o.tileNames == ["개발", "README.md", "API 명세"])
            #expect(o.model.pathBarNames == ["서비스 A"])
            #expect(o.model.iconItemCountText == "항목 3개")
        }
    }

    // MARK: 탐색

    @Test("[W28-enter-wing] Wing 이중 클릭·들어가기는 그 Wing으로 이동하고 선택을 비운다", arguments: [false, true])
    func enterWing(byMenu: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let dev = try o.id("개발")
            o.model.selectedNodeID = dev
            let before = try await o.revisions()

            if byMenu {
                #expect(o.model.canEnterSelected)
                await o.model.enterSelected()
            } else {
                await o.model.activateTile(dev)
            }

            #expect(o.model.iconLocationID == dev)
            #expect(o.tileNames == ["backend", "하위"])
            #expect(o.model.selectedNodeID == nil)
            #expect(o.model.pathBarNames == ["서비스 A", "개발"])
            #expect(o.model.iconTitle == "개발")
            #expect(o.model.iconSubtitle == "서비스 A")
            #expect(try await o.revisions() == before)
        }
    }

    enum Back: String, CaseIterable, Sendable { case up, back, pathRoot }

    @Test("[W28-navigate-back] 상위로·뒤로·경로 막대로 돌아가면 방금 있던 Wing을 선택하고 기록하지 않는다", arguments: Back.allCases)
    func navigateBack(way: Back) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let dev = try o.id("개발"), sub = try o.id("하위")
            o.model.enter(dev)
            o.model.enter(sub)
            let before = try await o.revisions()

            switch way {
            case .up: o.model.goUp()
            case .back: o.model.goBack()
            case .pathRoot: o.model.goTo(nil)
            }

            #expect(o.model.iconLocationID == (way == .pathRoot ? nil : dev))
            #expect(o.model.selectedNodeID == (way == .pathRoot ? dev : sub))
            #expect(try await o.revisions() == before)
        }
    }

    @Test("[W28-back-history] 뒤로 기록은 뒤로를 뺀 모든 위치 이동을 쌓고 다하면 꺼진다")
    func backHistory() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let dev = try o.id("개발"), sub = try o.id("하위")
            o.model.enter(dev)
            o.model.enter(sub)
            o.model.goTo(nil)

            var visited: [UUID?] = []
            for _ in 0..<3 {
                o.model.goBack()
                visited.append(o.model.iconLocationID)
            }
            #expect(visited == [sub, dev, nil])
            #expect(!o.model.canGoBack)
        }
    }

    @Test("[W28-back-to-removed-wing] 뒤로 대상 Wing이 없어졌으면 남은 가장 가까운 상위로 간다")
    func backToRemovedWing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let dev = try o.id("개발"), sub = try o.id("하위")
            o.model.enter(dev)
            o.model.enter(sub)
            o.model.goTo(nil)
            o.model.showList()
            o.model.selectedNodeID = sub
            o.model.beginRemove()
            await o.model.confirmRemove()
            o.model.showIcons()
            #expect(o.model.iconLocationID == nil)

            o.model.goBack()

            #expect(o.model.iconLocationID == dev)
        }
    }

    enum Disabled: String, CaseIterable, Sendable { case rootNoHistory, listView, afterBoardSwitch }

    @Test("[W28-navigation-capabilities] 실행할 수 없는 탐색 명령은 꺼져 있다", arguments: Disabled.allCases)
    func navigationCapabilities(state: Disabled) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            switch state {
            case .rootNoHistory:
                #expect(!o.model.canGoUp)
                #expect(!o.model.canGoBack)
            case .listView:
                o.model.enter(try o.id("개발"))
                o.model.selectedNodeID = try o.id("backend")
                o.model.showList()
                #expect(!o.model.canGoUp)
                #expect(!o.model.canEnterSelected)
                #expect(!o.model.canGoBack)
            case .afterBoardSwitch:
                o.model.enter(try o.id("개발"))
                await o.model.select(o.other)
                await o.model.select(o.project)
                #expect(!o.model.canGoBack)
            }
        }
    }

    @Test("[W28-open-from-tile] Bishop·웹 링크 이중 클릭·들어가기는 열기이고 위치·기록을 바꾸지 않는다", .tags(.A02), arguments: ["README.md", "API 명세"])
    func openFromTile(name: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let item = try o.id(name)
            o.model.selectedNodeID = item
            let before = try await o.revisions()

            if name == "README.md" { await o.model.activateTile(item) } else { await o.model.enterSelected() }

            #expect(o.harness.launcher.opened.count == 1)
            #expect(o.model.iconLocationID == nil)
            #expect(try await o.revisions() == before)
        }
    }

    enum Fallback: String, CaseIterable, Sendable { case removeSub, removeDev, boardSwitch }

    @Test("[W28-location-fallback] 보던 Wing이 없어지면 남은 가장 가까운 상위, Board를 바꾸면 최상위로 간다", arguments: Fallback.allCases)
    func locationFallback(change: Fallback) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let dev = try o.id("개발"), sub = try o.id("하위")
            o.model.enter(dev)
            o.model.enter(sub)
            switch change {
            case .removeSub, .removeDev:
                o.model.showList()
                o.model.selectedNodeID = change == .removeSub ? sub : dev
                o.model.beginRemove()
                await o.model.confirmRemove()
                o.model.showIcons()
            case .boardSwitch:
                await o.model.select(o.other)
                await o.model.select(o.project)
                o.model.showIcons()
            }
            #expect(o.model.iconLocationID == (change == .removeSub ? dev : nil))
        }
    }

    @Test("[W28-empty-wing] 빈 Wing은 항목 0개를 보이고 그곳에 놓은 파일을 그 Wing에 연결한다")
    func emptyWing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, emptyWing: true)
            o.model.showIcons()
            o.model.enter(try o.id("개발"))
            o.model.enter(try o.id("보관"))
            #expect(o.model.iconItems.isEmpty)
            #expect(o.model.pathBarNames == ["서비스 A", "개발", "보관"])
            #expect(o.model.iconItemCountText == "항목 0개")
            let before = try await o.revisions()

            let file = try TargetFiles.file(directory, "targets/new.md")
            #expect(o.model.canAcceptIconFileDrop(onTile: nil))
            #expect(await o.model.dropFilesInIconView([file], onTile: nil))

            let summaries = try await o.model.openedStore!.store.revisionSummaries(projectID: o.project)
            #expect(summaries.count == before + 1)
            #expect(summaries.last?.cause == .edited(.addLinkedItems))
            #expect(o.tileNames == ["new.md"])
        }
    }

    // MARK: 추가

    enum Addition: String, CaseIterable, Sendable { case wing, webLink, bishop }

    @Test("[W28-add-to-current-location] 아이콘 보기의 추가는 선택과 상관없이 현재 위치 끝에 들어가고 바로 보인다", .tags(.A04), arguments: Addition.allCases)
    func addToCurrentLocation(addition: Addition) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let dev = try o.id("개발")
            o.model.enter(dev)
            o.model.selectedNodeID = try o.id("하위")
            let before = try await o.revisions()

            let (name, cause): (String, RevisionCause.EditKind)
            switch addition {
            case .wing:
                o.model.beginAddGroup()
                o.model.nodeForm?.name = "문서"
                await o.model.confirmNodeForm()
                (name, cause) = ("문서", .addGroup)
            case .webLink:
                o.model.beginAddWebLink()
                o.model.nodeForm?.name = "위키"
                o.model.nodeForm?.url = "https://example.com/wiki"
                await o.model.confirmNodeForm()
                (name, cause) = ("위키", .addWebLink)
            case .bishop:
                o.harness.picker.results = [[try TargetFiles.file(directory, "targets/note.md")]]
                await o.model.addBishops()
                (name, cause) = ("note.md", .addLinkedItems)
            }

            let summaries = try await o.model.openedStore!.store.revisionSummaries(projectID: o.project)
            #expect(summaries.count == before + 1)
            #expect(summaries.last?.cause == .edited(cause))
            let node = try #require(o.model.loadedSnapshot?.node(named: name))
            #expect(node.parentID == dev)
            #expect(o.tileNames.last == name)
        }
    }

    @Test("[W28-add-cancel] 아이콘 보기의 추가 취소는 아무것도 바꾸지 않는다", .tags(.A04))
    func addCancel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            o.model.enter(try o.id("개발"))
            let before = (try await o.revisions(), o.tileNames, o.model.iconLocationID)

            o.model.beginAddGroup()
            o.model.cancelNodeForm()

            #expect(try await o.revisions() == before.0)
            #expect(o.tileNames == before.1)
            #expect(o.model.iconLocationID == before.2)
        }
    }

    // MARK: 끌어다 놓기

    struct NodeDrop: Sendable, CustomTestStringConvertible {
        var item: String
        var tile: String?
        var accepted: Bool
        var testDescription: String { "\(item) → \(tile ?? "빈 곳")" }
    }

    nonisolated static let nodeDrops: [NodeDrop] = [
        NodeDrop(item: "API 명세", tile: "개발", accepted: true),
        NodeDrop(item: "README.md", tile: "README.md", accepted: false),
        NodeDrop(item: "API 명세", tile: "README.md", accepted: false),
        NodeDrop(item: "README.md", tile: nil, accepted: false),
    ]

    @Test("[W28-drop-move] Wing 타일 위는 그 안으로 옮기고 자기 자신·Bishop·웹 링크 타일·같은 층 빈 곳은 받지 않는다", .tags(.A04), arguments: nodeDrops)
    func dropMove(drop: NodeDrop) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let item = try o.id(drop.item)
            let tile = try drop.tile.map { try o.id($0) }
            let before = (try await o.revisions(), o.tileNames)

            #expect(o.model.canAcceptIconNodeDrop(item, onTile: tile) == drop.accepted)
            #expect(await o.model.dropNodeInIconView(item, onTile: tile) == drop.accepted)

            let summaries = try await o.model.openedStore!.store.revisionSummaries(projectID: o.project)
            if drop.accepted {
                #expect(summaries.count == before.0 + 1)
                #expect(summaries.last?.cause == .edited(.move))
                #expect(o.model.loadedSnapshot?.node(named: drop.item)?.parentID == tile)
            } else {
                #expect(summaries.count == before.0)
                #expect(o.tileNames == before.1)
            }
        }
    }

    @Test("[W28-drop-move] Wing 안에서도 같은 층 타일을 빈 곳에 놓으면 받지 않고 순서를 바꾸지 않는다")
    func dropOnEmptyInsideWing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            o.model.enter(try o.id("개발"))
            let backend = try o.id("backend")
            let before = (try await o.revisions(), o.tileNames)
            #expect(!o.model.canAcceptIconNodeDrop(backend, onTile: nil))
            #expect(await o.model.dropNodeInIconView(backend, onTile: nil) == false)
            #expect(try await o.revisions() == before.0)
            #expect(o.tileNames == before.1)
        }
    }

    @Test("[W28-drop-move] 앱 안 항목을 폴더 Bishop 타일에 놓으면 받지 않는다")
    func dropOnFolderBishop() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            o.model.enter(try o.id("개발"))
            let sub = try o.id("하위"), backend = try o.id("backend")
            #expect(!o.model.canAcceptIconNodeDrop(sub, onTile: backend))
            #expect(await o.model.dropNodeInIconView(sub, onTile: backend) == false)
        }
    }

    struct FileDrop: Sendable, CustomTestStringConvertible {
        var tile: String?
        var parent: String?
        var testDescription: String { tile ?? "빈 곳" }
    }

    @Test("[W28-drop-link] Finder 파일은 Wing 타일·빈 곳에서 연결하고 Bishop 타일 위는 받지 않는다", arguments: [
        FileDrop(tile: "하위", parent: "하위"), FileDrop(tile: nil, parent: "개발"), FileDrop(tile: "backend", parent: nil),
    ])
    func dropLink(drop: FileDrop) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            o.model.enter(try o.id("개발"))
            let tile = try drop.tile.map { try o.id($0) }
            let file = try TargetFiles.file(directory, "targets/new.md")
            let before = try await o.revisions()
            #expect(o.model.canAcceptIconFileDrop(onTile: tile) == (drop.parent != nil))

            let accepted = await o.model.dropFilesInIconView([file], onTile: tile)

            #expect(accepted == (drop.parent != nil))
            if let parent = drop.parent {
                #expect(try await o.revisions() == before + 1)
                #expect(o.model.loadedSnapshot?.node(named: "new.md")?.parentID == (try o.id(parent)))
            } else {
                #expect(try await o.revisions() == before)
            }
        }
    }

    @Test("[W28-drop-link-on-weblink] Finder 파일을 웹 링크 타일에 놓으면 받지 않는다")
    func dropLinkOnWebLink() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let link = try o.id("API 명세")
            let before = try await o.revisions()
            #expect(!o.model.canAcceptIconFileDrop(onTile: link))
            #expect(await o.model.dropFilesInIconView([try TargetFiles.file(directory, "targets/new.md")], onTile: link) == false)
            #expect(try await o.revisions() == before)
        }
    }

    @Test("[W28-drop-save-failure] 드롭 이동 저장 실패는 안내하고 타일·위치·기록을 유지한다")
    func dropSaveFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let before = (try await o.revisions(), o.tileNames)
            o.harness.fault.failNext()

            await o.model.dropNodeInIconView(try o.id("API 명세"), onTile: try o.id("개발"))

            #expect(o.model.linkNotice?.kind == .saveFailed)
            #expect(try await o.revisions() == before.0)
            #expect(o.tileNames == before.1)
            #expect(o.model.iconLocationID == nil)
        }
    }

    // MARK: 선택·연결 상태·키보드

    @Test("[W28-select-checks-status] 타일 선택(클릭·방향키)은 그 Bishop만 한 번 확인하고 기록하지 않는다", arguments: [false, true])
    func selectChecksStatus(byArrow: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.readmeURL)
            o.model.showIcons()
            let readme = try o.id("README.md")
            let before = try await o.revisions()

            if byArrow {
                o.model.selectedNodeID = try o.id("개발")
                await o.model.selectNeighbor(.right, columns: 3)
            } else {
                await o.model.selectNode(readme)
            }

            #expect(o.model.selectedNodeID == readme)
            #expect(o.harness.bookmarks.scopedResolutions == ["README.md"])
            #expect(o.model.displayedStatus(of: readme) == .missing)
            let node = try #require(o.model.loadedSnapshot?.node(named: "README.md"))
            #expect(o.model.accessibilityLabel(for: node).contains("대상 없음"))
            #expect(try await o.revisions() == before)
        }
    }

    enum NoCheck: String, CaseIterable, Sendable { case switchView, switchWithSelection, enterAndUp, back }

    @Test("[W28-navigation-no-check] 보기 전환·들어가기·위로·뒤로는 접근 정보를 해석하지 않는다", arguments: NoCheck.allCases)
    func navigationNoCheck(action: NoCheck) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            switch action {
            case .switchView:
                o.model.showIcons()
            case .switchWithSelection:
                o.model.selectedNodeID = try o.id("README.md")
                o.model.showIcons()
                o.model.showList()
            case .enterAndUp:
                o.model.showIcons()
                o.model.enter(try o.id("개발"))
                o.model.goUp()
            case .back:
                o.model.showIcons()
                o.model.enter(try o.id("개발"))
                o.model.goBack()
            }
            #expect(o.harness.bookmarks.scopedResolutions.isEmpty)
        }
    }

    struct Arrow: Sendable, CustomTestStringConvertible {
        var start: Int?
        var direction: BoardBrowserModel.GridDirection
        var end: Int
        var testDescription: String { "\(start.map(String.init) ?? "없음") \(direction) → \(end)" }
    }

    /// 1부터 센 타일 번호. 7개를 한 줄에 3개씩: [1 2 3] [4 5 6] [7].
    nonisolated static let arrows: [Arrow] = [
        Arrow(start: 1, direction: .right, end: 2), Arrow(start: 3, direction: .right, end: 3),
        Arrow(start: 2, direction: .down, end: 5), Arrow(start: 6, direction: .down, end: 6),
        Arrow(start: 5, direction: .up, end: 2), Arrow(start: 1, direction: .left, end: 1),
        Arrow(start: 7, direction: .up, end: 4), Arrow(start: nil, direction: .right, end: 1),
    ]

    @Test("[W28-arrow-selection] 방향키는 열 수 기준으로 격자 선택을 옮기고 경계에서는 그대로다", arguments: arrows)
    func arrowSelection(arrow: Arrow) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory.appending(path: "browser"))
            let files = try (1...7).map { try TargetFiles.file(directory, "targets/\($0).txt") }
            var project = UUID()
            try await seedStore(in: directory, at: harness.url) { seed in
                project = try await makeBoard(seed, "일곱")
                _ = try await seed.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: files))
            }
            await harness.model.start()
            await harness.model.select(project)
            harness.model.showIcons()
            let ids = harness.model.iconItems.map(\.id)
            harness.model.selectedNodeID = arrow.start.map { ids[$0 - 1] }

            await harness.model.selectNeighbor(arrow.direction, columns: 3)

            #expect(harness.model.selectedNodeID == ids[arrow.end - 1])
        }
    }

    @Test("[W28-arrow-empty-wing] 빈 Wing에서는 방향키가 아무것도 고르지 않는다")
    func arrowEmptyWing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, emptyWing: true)
            o.model.showIcons()
            o.model.enter(try o.id("개발"))
            let empty = try o.id("보관")
            o.model.enter(empty)
            let before = try await o.revisions()

            await o.model.selectNeighbor(.right, columns: 3)
            await o.model.selectNeighbor(.down, columns: 3)

            #expect(o.model.selectedNodeID == nil)
            #expect(o.model.iconLocationID == empty)
            #expect(try await o.revisions() == before)
        }
    }

    @Test("[W28-shared-commands] 아이콘 보기에서도 위로 이동이 같은 기록 규칙으로 동작하고 선택을 유지한다", .tags(.A04))
    func sharedCommands() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.showIcons()
            let readme = try o.id("README.md")
            o.model.selectedNodeID = readme
            let before = try await o.revisions()

            await o.model.moveSelectedUp()

            #expect(o.tileNames == ["README.md", "개발", "API 명세"])
            let summaries = try await o.model.openedStore!.store.revisionSummaries(projectID: o.project)
            #expect(summaries.count == before + 1)
            #expect(summaries.last?.cause == .edited(.move))
            #expect(o.model.selectedNodeID == readme)
        }
    }

    // MARK: Bishop 아이콘 설정

    @Test("[W28-bishop-icon-setting] 설정에 따라 기호 심볼 또는 확장자 기준 일반 아이콘을 쓰고 대상에 접근하지 않는다")
    func bishopIconSetting() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let node = { (name: String) throws -> ConfigurationNode in try #require(o.model.loadedSnapshot?.node(named: name)) }
            let makefile = ConfigurationNode(id: UUID(), kind: .file, displayName: "Makefile", sortIndex: 0, recordedPath: "/src/Makefile")
            let before = try await o.revisions()

            #expect(o.model.bishopIconStyle == .symbol)
            #expect(TileIcon.of(try node("README.md"), style: .symbol) == .bishop(purpose: nil))
            #expect(TileIcon.of(try node("backend"), style: .symbol) == .bishopFolder)
            #expect(TileIcon.of(try node("개발"), style: .symbol) == .systemSymbol("folder"))
            #expect(TileIcon.of(try node("API 명세"), style: .symbol) == .systemSymbol("link"))

            o.model.bishopIconStyle = .fileType
            #expect(TileIcon.of(try node("설계.key"), style: .fileType) == .fileType(identifier: TileIcon.typeIdentifier(forExtension: "key")))
            #expect(TileIcon.of(makefile, style: .fileType) == .fileType(identifier: TileIcon.genericDocumentIdentifier))
            #expect(TileIcon.of(try node("backend"), style: .fileType) == .genericFolder)
            #expect(TileIcon.of(try node("개발"), style: .fileType) == .systemSymbol("folder"))
            #expect(TileIcon.of(try node("API 명세"), style: .fileType) == .systemSymbol("link"))
            #expect(o.harness.bookmarks.scopedResolutions.isEmpty)
            #expect(try await o.revisions() == before)
        }
    }

    @Test("[W28-bishop-icon-setting-remembered] Bishop 아이콘 설정은 다시 실행해도 기억하고 기록하지 않는다")
    func bishopIconSettingRemembered() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try await o.revisions()
            o.model.bishopIconStyle = .fileType

            let relaunched = BrowserHarness(directory: directory.appending(path: "browser"), lastBoard: o.lastBoard)
            #expect(relaunched.model.bishopIconStyle == .fileType)
            #expect(try await o.revisions() == before)
        }
    }

    // MARK: 보관된 Board

    @Test("[W28-archived] 보관된 Board의 아이콘 보기는 탐색·열기만 되고 드롭·추가·이동은 받지 않는다")
    func archived() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            o.model.showIcons()
            let dev = try o.id("개발"), readme = try o.id("README.md"), api = try o.id("API 명세")
            let before = try await o.revisions()

            o.model.enter(dev)
            #expect(o.model.iconLocationID == dev)
            o.model.goUp()
            #expect(o.model.iconLocationID == nil)
            await o.model.activateTile(readme)
            #expect(o.harness.launcher.opened.count == 1)

            #expect(!o.model.canAcceptIconNodeDrop(api, onTile: dev))
            #expect(await o.model.dropNodeInIconView(api, onTile: dev) == false)
            let file = try TargetFiles.file(directory, "targets/new.md")
            #expect(!o.model.canAcceptIconFileDrop(onTile: nil))
            #expect(await o.model.dropFilesInIconView([file], onTile: nil) == false)
            #expect(!o.model.canAcceptIconFileDrop(onTile: dev))
            #expect(!o.model.canAddToBoard)
            o.model.selectedNodeID = readme
            #expect(!o.model.canMoveSelectedUp)
            #expect(try await o.revisions() == before)
        }
    }
}
