import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("그룹·웹 링크 만들기와 이름·URL 편집 화면 (W11)")
struct NodeEditingModelTests {
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let group: UUID
        let backend: UUID
        let link: UUID
        let directory: URL
    }

    /// 그룹 "개발" 안에 Bishop 폴더 "backend", 최상위 웹 링크 "API 명세"가 있는 Board를 열고 선택한다.
    private func opened(_ directory: URL, archived: Bool = false) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let backend = try TargetFiles.folder(directory, "targets/backend")
        var ids = (UUID(), UUID(), UUID(), UUID())
        try await seedStore(in: directory, at: harness.url) { seed in
            let project = try await makeBoard(seed, "서비스 A")
            let group = try #require(try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed)
            let groupID = try #require(group.snapshot.node(named: "개발")).id
            _ = try await seed.linking.link(LinkRequest(projectID: project, parentID: groupID, position: nil, urls: [backend]))
            let link = try #require(try await seed.service.apply(
                .addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil), to: project
            ).committed)
            ids = (project, groupID, try #require(link.snapshot.node(named: "backend")).id, try #require(link.snapshot.node(named: "API 명세")).id)
            if archived { try await seed.store.setArchived(project, at: date(100)) }
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, project: ids.0, group: ids.1, backend: ids.2, link: ids.3, directory: directory)
    }

    private func revisions(_ o: Opened) async throws -> [RevisionSummary] {
        try await o.harness.model.openedStore!.store.revisionSummaries(projectID: o.project)
    }

    enum Selection: String, CaseIterable, Sendable { case none, group, bishop, link }

    private func select(_ o: Opened, _ selection: Selection) {
        o.harness.model.selectedNodeID = switch selection {
        case .none: nil
        case .group: o.group
        case .bishop: o.backend
        case .link: o.link
        }
    }

    private func expectedParent(_ o: Opened, _ selection: Selection) -> UUID? {
        selection == .group || selection == .bishop ? o.group : nil
    }

    // MARK: 그룹

    @Test("[W11-add-group-location] 그룹을 만들면 선택한 위치의 끝에 revision 하나로 추가된다", .tags(.A01), arguments: Selection.allCases)
    func addGroupLocation(selection: Selection) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            select(o, selection)
            let before = try await revisions(o).count
            let listing = fileListing(directory)

            o.harness.model.beginAddGroup()
            o.harness.model.nodeForm?.name = "  공통 "
            await o.harness.model.confirmNodeForm()

            #expect(o.harness.model.nodeForm == nil)
            let summaries = try await revisions(o)
            #expect(summaries.count == before + 1)
            #expect(summaries.last?.cause == .edited(.addGroup))
            let parent = expectedParent(o, selection)
            let snapshot = try #require(o.harness.model.loadedSnapshot)
            let siblings = snapshot.nodes.filter { $0.parentID == parent }.sorted { $0.sortIndex < $1.sortIndex }
            #expect(siblings.last?.displayName == "공통")
            #expect(siblings.last?.kind == .group)
            #expect(fileListing(directory).subtracting(listing).allSatisfy { $0.contains("Fianchetto.store") })
        }
    }

    @Test("[W11-nested-groups] 그룹 안에 그룹을 여러 단계로 만들 수 있다", .tags(.A01))
    func nestedGroups() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try await revisions(o).count

            o.harness.model.selectedNodeID = o.group
            o.harness.model.beginAddGroup()
            o.harness.model.nodeForm?.name = "하위"
            await o.harness.model.confirmNodeForm()
            let child = try #require(o.harness.model.loadedSnapshot?.node(named: "하위"))
            o.harness.model.selectedNodeID = child.id
            o.harness.model.beginAddGroup()
            o.harness.model.nodeForm?.name = "더 하위"
            await o.harness.model.confirmNodeForm()

            let deeper = try #require(o.harness.model.loadedSnapshot?.node(named: "더 하위"))
            #expect(child.parentID == o.group)
            #expect(deeper.parentID == child.id)
            #expect(try await revisions(o).count == before + 2)
        }
    }

    // MARK: 웹 링크

    @Test("[W11-add-web-link] 웹 링크를 만들면 이름과 정리한 URL로 선택한 위치의 끝에 revision 하나가 남는다", arguments: Selection.allCases)
    func addWebLink(selection: Selection) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            select(o, selection)

            o.harness.model.beginAddWebLink()
            o.harness.model.nodeForm?.name = "디자인 시안"
            o.harness.model.nodeForm?.url = " https://figma.com/file/1 "
            await o.harness.model.confirmNodeForm()

            #expect(o.harness.model.nodeForm == nil)
            #expect(try await revisions(o).last?.cause == .edited(.addWebLink))
            let snapshot = try #require(o.harness.model.loadedSnapshot)
            let parent = expectedParent(o, selection)
            let last = snapshot.nodes.filter { $0.parentID == parent }.sorted { $0.sortIndex < $1.sortIndex }.last
            #expect(last?.displayName == "디자인 시안")
            #expect(last?.url == "https://figma.com/file/1")
        }
    }

    @Test("[W11-web-link-invalid-input] 웹 링크 입력이 유효하지 않으면 입력을 유지하고 이유를 알린다", arguments: [
        ("디자인 시안", "ftp://example.com", BoardBrowserModel.FormMessage.invalidURL),
        ("디자인 시안", "example.com", .invalidURL),
        ("디자인 시안", "", .invalidURL),
        ("   ", "https://figma.com", .nameRequired),
    ])
    func webLinkInvalidInput(name: String, url: String, message: BoardBrowserModel.FormMessage) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try await revisions(o).count

            o.harness.model.beginAddWebLink()
            o.harness.model.nodeForm?.name = name
            o.harness.model.nodeForm?.url = url
            await o.harness.model.confirmNodeForm()

            #expect(o.harness.model.nodeForm?.name == name)
            #expect(o.harness.model.nodeForm?.url == url)
            #expect(o.harness.model.nodeForm?.message == message)
            #expect(try await revisions(o).count == before)
        }
    }

    // MARK: 같은 이름

    enum SameName: String, CaseIterable, Sendable { case group, link, rename }

    @Test("[W11-same-name-siblings-allowed] 같은 부모 아래 같은 표시 이름을 허용하고 병합하지 않는다", arguments: SameName.allCases)
    func sameNameSiblingsAllowed(kind: SameName) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let name: String
            switch kind {
            case .group:
                name = "개발"
                o.harness.model.beginAddGroup()
                o.harness.model.nodeForm?.name = name
            case .link:
                name = "API 명세"
                o.harness.model.beginAddWebLink()
                o.harness.model.nodeForm?.name = name
                o.harness.model.nodeForm?.url = "https://example.com/other"
            case .rename:
                name = "backend"
                o.harness.model.selectedNodeID = o.group
                o.harness.model.beginAddGroup()
                o.harness.model.nodeForm?.name = "공통"
                await o.harness.model.confirmNodeForm()
                o.harness.model.selectedNodeID = try #require(o.harness.model.loadedSnapshot?.node(named: "공통")).id
                o.harness.model.beginRenameNode()
                o.harness.model.nodeForm?.name = name
            }
            await o.harness.model.confirmNodeForm()

            #expect(o.harness.model.nodeForm == nil)
            let same = try #require(o.harness.model.loadedSnapshot).nodes.filter { $0.displayName == name }
            #expect(same.count == 2)
            #expect(Set(same.map(\.id)).count == 2)
            #expect(Set(same.map(\.parentID)).count == 1)
        }
    }

    // MARK: 이름 변경

    @Test("[W11-rename-node] 항목 이름을 바꾸면 UUID와 위치는 그대로이고 과거 revision은 옛 이름을 가진다", .tags(.A04), arguments: [Selection.group, .bishop, .link])
    func renameNode(selection: Selection) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            select(o, selection)
            let id = try #require(o.harness.model.selectedNodeID)
            let before = try #require(o.harness.model.loadedSnapshot?.node(id))

            o.harness.model.beginRenameNode()
            #expect(o.harness.model.nodeForm?.name == before.displayName)
            o.harness.model.nodeForm?.name = "새 이름"
            await o.harness.model.confirmNodeForm()

            #expect(o.harness.model.nodeForm == nil)
            let summaries = try await revisions(o)
            #expect(summaries.last?.cause == .edited(.renameNode))
            let after = try #require(o.harness.model.loadedSnapshot?.node(id))
            #expect(after.displayName == "새 이름")
            #expect(after.parentID == before.parentID && after.sortIndex == before.sortIndex)
            #expect(after.referenceID == before.referenceID && after.url == before.url && after.kind == before.kind)
            let previous = try await o.harness.model.openedStore!.store.snapshot(revisionID: summaries[summaries.count - 2].id)
            #expect(previous.node(id)?.displayName == before.displayName)
        }
    }

    @Test("[W11-rename-unchanged-or-blank] 이름 변경을 같은 값으로 확정하거나 빈 이름이면 기록하지 않는다", .tags(.A04), arguments: [" backend ", "   "])
    func renameUnchangedOrBlank(name: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.model.selectedNodeID = o.backend
            let before = try await revisions(o).count

            o.harness.model.beginRenameNode()
            o.harness.model.nodeForm?.name = name
            await o.harness.model.confirmNodeForm()

            if name == "   " {
                #expect(o.harness.model.nodeForm?.message == .nameRequired)
            } else {
                #expect(o.harness.model.nodeForm == nil)
            }
            #expect(o.harness.model.loadedSnapshot?.node(o.backend)?.displayName == "backend")
            #expect(try await revisions(o).count == before)
        }
    }

    @Test("[W11-rename-requires-selection] 이름 변경은 트리 항목을 선택했을 때만 시작한다")
    func renameRequiresSelection() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.model.selectedNodeID = nil

            o.harness.model.beginRenameNode()

            #expect(o.harness.model.nodeForm == nil)
        }
    }

    // MARK: URL 변경

    @Test("[W11-change-url] 웹 링크 URL을 바꾸면 UUID와 이름은 그대로이고 revision 하나가 남는다", .tags(.A04))
    func changeURL() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.model.selectedNodeID = o.link

            o.harness.model.beginChangeURL()
            #expect(o.harness.model.nodeForm?.url == "https://example.com/api")
            o.harness.model.nodeForm?.url = "https://example.com/v2"
            await o.harness.model.confirmNodeForm()

            #expect(o.harness.model.nodeForm == nil)
            let summaries = try await revisions(o)
            #expect(summaries.last?.cause == .edited(.changeURL))
            let after = try #require(o.harness.model.loadedSnapshot?.node(o.link))
            #expect(after.url == "https://example.com/v2" && after.displayName == "API 명세")
            let previous = try await o.harness.model.openedStore!.store.snapshot(revisionID: summaries[summaries.count - 2].id)
            #expect(previous.node(o.link)?.url == "https://example.com/api")
        }
    }

    @Test("[W11-change-url-unchanged-or-invalid] URL 변경을 같은 값으로 확정하거나 유효하지 않은 URL이면 기록하지 않는다", arguments: [" https://example.com/api ", "ftp://example.com"])
    func changeURLUnchangedOrInvalid(url: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.model.selectedNodeID = o.link
            let before = try await revisions(o).count

            o.harness.model.beginChangeURL()
            o.harness.model.nodeForm?.url = url
            await o.harness.model.confirmNodeForm()

            if url.hasPrefix("ftp") {
                #expect(o.harness.model.nodeForm?.message == .invalidURL)
            } else {
                #expect(o.harness.model.nodeForm == nil)
            }
            #expect(try await revisions(o).count == before)
        }
    }

    @Test("[W11-change-url-requires-link] URL 변경은 웹 링크를 선택했을 때만 시작한다", arguments: [Selection.group, .bishop, .none])
    func changeURLRequiresLink(selection: Selection) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            select(o, selection)

            o.harness.model.beginChangeURL()

            #expect(o.harness.model.nodeForm == nil)
        }
    }

    // MARK: 공통

    enum Action: String, CaseIterable, Sendable { case addGroup, addLink, rename, changeURL }

    private func begin(_ o: Opened, _ action: Action) {
        switch action {
        case .addGroup:
            o.harness.model.selectedNodeID = nil
            o.harness.model.beginAddGroup()
        case .addLink:
            o.harness.model.selectedNodeID = nil
            o.harness.model.beginAddWebLink()
        case .rename:
            o.harness.model.selectedNodeID = o.backend
            o.harness.model.beginRenameNode()
        case .changeURL:
            o.harness.model.selectedNodeID = o.link
            o.harness.model.beginChangeURL()
        }
    }

    /// 각 입력 창에 유효한 새 값을 넣는다. 읽기와 쓰기를 한 식에 섞지 않는다(동시 접근 금지).
    private func fillValid(_ o: Opened, _ action: Action) {
        guard var form = o.harness.model.nodeForm else { return }
        if action != .changeURL { form.name = "새 값" }
        if action == .addLink || action == .changeURL { form.url = "https://example.com/new" }
        o.harness.model.nodeForm = form
    }

    @Test("[W11-cancel-records-nothing] 입력 창을 취소하면 아무것도 기록하지 않는다", .tags(.A04), arguments: Action.allCases)
    func cancelRecordsNothing(action: Action) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try await revisions(o).count
            let snapshot = o.harness.model.loadedSnapshot

            begin(o, action)
            #expect(o.harness.model.nodeForm != nil)
            fillValid(o, action)
            o.harness.model.cancelNodeForm()

            #expect(o.harness.model.nodeForm == nil)
            #expect(try await revisions(o).count == before)
            #expect(o.harness.model.loadedSnapshot == snapshot)
        }
    }

    @Test("[W11-save-failure-keeps-input] 저장이 실패하면 입력을 유지하고 저장하지 못했다고 알린다", .tags(.A13), arguments: Action.allCases)
    func saveFailureKeepsInput(action: Action) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try await revisions(o).count
            let snapshot = o.harness.model.loadedSnapshot
            begin(o, action)
            fillValid(o, action)
            let draft = o.harness.model.nodeForm
            o.harness.fault.failNext()

            await o.harness.model.confirmNodeForm()

            #expect(o.harness.model.nodeForm?.message == .saveFailed)
            #expect(o.harness.model.nodeForm?.name == draft?.name && o.harness.model.nodeForm?.url == draft?.url)
            #expect(o.harness.model.nodeForm?.isSaving == false)
            #expect(try await revisions(o).count == before)
            #expect(o.harness.model.loadedSnapshot == snapshot)
        }
    }

    @Test("[W11-save-failure-keeps-input] 저장 중에는 확정을 한 번만 받는다")
    func singleConfirmWhileSaving() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try await revisions(o).count
            begin(o, .addGroup)
            fillValid(o, .addGroup)

            async let first: Void = o.harness.model.confirmNodeForm()
            async let second: Void = o.harness.model.confirmNodeForm()
            _ = await (first, second)

            #expect(try await revisions(o).count == before + 1)
        }
    }

    @Test("[W11-archived-blocks-edits] 보관된 Board에서는 편집을 시작하지 않고 안내한다", arguments: Action.allCases)
    func archivedBlocksEdits(action: Action) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            let before = try await revisions(o).count
            // 웹 링크가 아닌 그룹을 선택해도 URL 변경은 보관 안내가 먼저다.
            o.harness.model.selectedNodeID = action == .changeURL ? o.group : o.link

            switch action {
            case .addGroup: o.harness.model.beginAddGroup()
            case .addLink: o.harness.model.beginAddWebLink()
            case .rename: o.harness.model.beginRenameNode()
            case .changeURL: o.harness.model.beginChangeURL()
            }

            #expect(o.harness.model.nodeForm == nil)
            #expect(o.harness.model.linkNotice?.kind == .archived)
            #expect(try await revisions(o).count == before)
        }
    }

    @Test("[W11-edits-require-board] 선택한 Board가 없으면 편집을 시작하지 않는다", arguments: Action.allCases)
    func editsRequireBoard(action: Action) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            await harness.model.start()

            switch action {
            case .addGroup: harness.model.beginAddGroup()
            case .addLink: harness.model.beginAddWebLink()
            case .rename: harness.model.beginRenameNode()
            case .changeURL: harness.model.beginChangeURL()
            }

            #expect(harness.model.nodeForm == nil)
            #expect(harness.model.linkNotice == nil)
        }
    }

    private func fileListing(_ directory: URL) -> Set<String> {
        Set(FileManager.default.enumerator(atPath: directory.path)?.compactMap { $0 as? String } ?? [])
    }
}
