import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("Bishop 추가와 Finder 드롭 화면 (W08)")
struct BishopLinkingModelTests {
    // MARK: Bishop 추가

    enum Selection: String, CaseIterable, Sendable { case none, group, bishop, webLink }

    @Test("[W08-add-location-by-selection] Bishop 추가는 선택한 항목에 따라 연결할 위치를 정한다", arguments: Selection.allCases)
    func addLocationFollowsSelection(selection: Selection) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, ids) = try await openedBoard(directory)
            harness.model.selectedNodeID = switch selection {
            case .none: nil
            case .group: ids.group
            case .bishop: ids.backend
            case .webLink: ids.link
            }
            harness.picker.results = [[try TargetFiles.file(directory, "targets/design.md")]]

            await harness.model.addBishops()

            let snapshot = try #require(harness.model.loadedSnapshot)
            let added = try #require(snapshot.node(named: "design.md"))
            let expectedParent: UUID? = (selection == .group || selection == .bishop) ? ids.group : nil
            #expect(added.parentID == expectedParent)
            #expect(added.sortIndex == snapshot.nodes.filter { $0.parentID == expectedParent }.count - 1)
        }
    }

    @Test("[W08-picker-cancel] 파일 선택 창을 취소하면 아무것도 기록하지 않는다")
    func pickerCancelRecordsNothing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, ids) = try await openedBoard(directory)
            harness.picker.results = [nil]
            let before = try await revisionCount(harness, ids.project)

            await harness.model.addBishops()

            #expect(harness.picker.calls == 1)
            #expect(try await revisionCount(harness, ids.project) == before)
            #expect(harness.model.linkNotice == nil)
        }
    }

    @Test("[W08-add-requires-board] Board를 선택하지 않았으면 Bishop 추가는 아무 일도 하지 않는다")
    func addRequiresBoard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            await harness.model.start()

            await harness.model.addBishops()

            #expect(harness.picker.calls == 0)
        }
    }

    @Test("[W08-failure-message-and-retry] 연결에 실패하면 실패한 대상 이름과 다시 시도를 보여 주고, 다시 시도하면 같은 Board·같은 위치에 다시 연결한다")
    func failureMessageAndRetry() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, ids) = try await openedBoard(directory, extraBoard: true)
            harness.model.selectedNodeID = ids.group
            harness.bookmarks.fail(["notes.txt"], times: 1)
            harness.picker.results = [[
                try TargetFiles.file(directory, "targets/design.md"), try TargetFiles.file(directory, "targets/notes.txt"),
            ]]

            await harness.model.addBishops()

            let notice = try #require(harness.model.linkNotice)
            #expect(notice.kind == .unreachable(["notes.txt"]))
            #expect(notice.canRetry)
            let text = harness.model.noticeText(notice)
            #expect(text.contains("notes.txt"))
            for word in ["북마크", "bookmark", "Bookmark", "DB", "JSON"] { #expect(!text.contains(word)) }

            // 다른 Board를 고른 뒤에도 다시 시도는 처음 Board·위치로 연결한다.
            await harness.model.select(try #require(harness.model.board(named: "서비스 B")).id)
            await harness.model.retryLink()

            #expect(harness.model.linkNotice == nil)
            let original = try await harness.model.openedStore!.store.currentSnapshot(projectID: ids.project)
            let children = original.nodes.filter { $0.parentID == ids.group }.sorted { $0.sortIndex < $1.sortIndex }.map(\.displayName)
            #expect(children.suffix(2) == ["design.md", "notes.txt"])
        }
    }

    @Test("[W08-dismiss-failure-records-nothing] 실패 안내를 닫으면 아무것도 기록하지 않는다")
    func dismissRecordsNothing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, ids) = try await openedBoard(directory)
            harness.bookmarks.fail(["notes.txt"])
            harness.picker.results = [[try TargetFiles.file(directory, "targets/notes.txt")]]
            await harness.model.addBishops()
            let before = try await revisionCount(harness, ids.project)

            harness.model.dismissLinkNotice()

            #expect(harness.model.linkNotice == nil)
            #expect(try await revisionCount(harness, ids.project) == before)
        }
    }

    @Test("[W08-save-failure-message-and-retry] 저장에 실패하면 저장하지 못했다는 안내와 다시 시도를 보여 준다", .tags(.A13))
    func saveFailureMessageAndRetry() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, ids) = try await openedBoard(directory)
            let before = try await revisionCount(harness, ids.project)
            let tree = harness.model.loadedSnapshot
            harness.fault.failNext()
            harness.picker.results = [[try TargetFiles.file(directory, "targets/design.md")]]

            await harness.model.addBishops()

            #expect(harness.model.linkNotice?.kind == .saveFailed)
            #expect(harness.model.linkNotice?.canRetry == true)
            #expect(try await revisionCount(harness, ids.project) == before)
            #expect(harness.model.loadedSnapshot == tree)

            await harness.model.retryLink()
            #expect(harness.model.loadedSnapshot?.node(named: "design.md") != nil)
        }
    }

    @Test("[W08-archived-board-ui] 보관된 Board에서는 Bishop 추가와 드롭이 아무것도 바꾸지 않는다")
    func archivedBoardUI() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            var project = UUID()
            try await seedStore(in: directory, at: harness.url) { seed in
                project = try await makeBoard(seed, "옛 프로젝트")
                try await seed.store.setArchived(project, at: date(100))
            }
            await harness.model.start()
            await harness.model.select(project)
            let before = try await revisionCount(harness, project)

            await harness.model.addBishops()
            #expect(harness.picker.calls == 0)
            #expect(harness.model.linkNotice?.kind == .archived)

            let file = try TargetFiles.file(directory, "targets/design.md")
            #expect(!harness.model.canAcceptDrop(on: nil))
            #expect(await harness.model.drop([file], on: nil) == false)
            #expect(try await revisionCount(harness, project) == before)
        }
    }

    @Test("[W08-tree-refreshes] 연결이 끝나면 현재 구성 트리를 새 구성으로 바꾼다")
    func treeRefreshes() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, _) = try await openedBoard(directory)
            harness.picker.results = [[try TargetFiles.file(directory, "targets/design.md")]]

            await harness.model.addBishops()

            #expect(harness.model.tree.map(\.node.displayName).contains("design.md"))
        }
    }

    // MARK: Finder 드롭

    enum DropTarget: String, CaseIterable, Sendable { case root, group, bishopFolder, bishopFile, webLink }

    @Test("[W08-drop-target-rules] Finder에서 끌어온 파일은 놓은 곳이 그룹이나 최상위일 때만 받는다", arguments: DropTarget.allCases)
    func dropTargetRules(target: DropTarget) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, ids) = try await openedBoard(directory)
            let nodeID: UUID? = switch target {
            case .root: nil
            case .group: ids.group
            case .bishopFolder: ids.backend
            case .bishopFile: ids.note
            case .webLink: ids.link
            }
            let files = [try TargetFiles.file(directory, "targets/design.md"), try TargetFiles.file(directory, "targets/notes.txt")]
            let before = try await revisionCount(harness, ids.project)
            let accepts = target == .root || target == .group

            #expect(harness.model.canAcceptDrop(on: nodeID) == accepts)
            #expect(await harness.model.drop(files, on: nodeID) == accepts)

            #expect(try await revisionCount(harness, ids.project) == before + (accepts ? 1 : 0))
            if accepts {
                let snapshot = try #require(harness.model.loadedSnapshot)
                let siblings = snapshot.nodes.filter { $0.parentID == nodeID }.sorted { $0.sortIndex < $1.sortIndex }.map(\.displayName)
                #expect(siblings.suffix(2) == ["design.md", "notes.txt"])
            }
        }
    }

    @Test("[W08-drop-folder] Finder에서 폴더를 끌어다 놓으면 Bishop 폴더로 연결한다")
    func dropFolder() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, _) = try await openedBoard(directory)

            #expect(await harness.model.drop([try TargetFiles.folder(directory, "targets/assets")], on: nil))

            let assets = try #require(harness.model.loadedSnapshot?.node(named: "assets"))
            #expect(assets.kind == .folder)
            #expect(assets.parentID == nil)
        }
    }

    @Test("[W08-drop-non-file-rejected] 파일이 아닌 항목을 끌어다 놓으면 받지 않는다")
    func dropNonFileRejected() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, ids) = try await openedBoard(directory)
            let before = try await revisionCount(harness, ids.project)

            #expect(await harness.model.drop([try #require(URL(string: "https://example.com"))], on: nil) == false)
            #expect(await harness.model.drop([], on: nil) == false)
            #expect(try await revisionCount(harness, ids.project) == before)
        }
    }

    // MARK: 선택 창·메뉴

    @Test("[W08-picker-configuration] 파일 선택 창은 파일과 폴더를 여러 개 고를 수 있다")
    func pickerConfiguration() {
        let configuration = TargetPicker.configuration
        #expect(configuration.canChooseFiles)
        #expect(configuration.canChooseDirectories)
        #expect(configuration.allowsMultipleSelection)
        #expect(!configuration.canCreateDirectories)
    }

    // MARK: 도우미

    struct IDs {
        var project: UUID
        var group: UUID
        var backend: UUID
        var note: UUID
        var link: UUID
    }

    /// Board "서비스 A": 그룹 "개발" 안에 Bishop 폴더 "backend", 최상위 Bishop 파일 "설계 메모"와 웹 링크 "API 명세". 선택된 상태로 연다.
    private func openedBoard(_ directory: URL, extraBoard: Bool = false) async throws -> (BrowserHarness, IDs) {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        var ids = IDs(project: UUID(), group: UUID(), backend: UUID(), note: UUID(), link: UUID())
        let backendFolder = try TargetFiles.folder(directory, "targets/backend")
        let noteFile = try TargetFiles.file(directory, "targets/설계 메모.md")
        try await seedStore(in: directory, at: harness.url) { seed in
            let project = try await makeBoard(seed, "서비스 A")
            let group = try #require(try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed)
            let groupID = try #require(group.snapshot.node(named: "개발")).id
            _ = try await seed.linking.link(LinkRequest(projectID: project, parentID: groupID, position: nil, urls: [backendFolder]))
            _ = try await seed.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [noteFile]))
            let link = try #require(try await seed.service.apply(
                .addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil), to: project
            ).committed)
            ids = IDs(
                project: project, group: groupID,
                backend: try #require(link.snapshot.node(named: "backend")).id,
                note: try #require(link.snapshot.node(named: "설계 메모.md")).id,
                link: try #require(link.snapshot.node(named: "API 명세")).id
            )
            if extraBoard { _ = try await makeBoard(seed, "서비스 B") }
        }
        await harness.model.start()
        await harness.model.select(ids.project)
        return (harness, ids)
    }

    private func revisionCount(_ harness: BrowserHarness, _ project: UUID) async throws -> Int {
        try await harness.model.openedStore!.store.revisionSummaries(projectID: project).count
    }
}
