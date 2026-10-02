import Foundation
import Testing
@testable import Fianchetto

/// 접힌 그룹 안에 넣은 항목이 트리에 보이지 않던 버그의 재현과 회귀 테스트.
/// 그룹 안에 항목을 넣거나 옮기면 그 그룹과 모든 상위 그룹을 펼친다.
@MainActor
@Suite("그룹 안에 넣은 항목이 보이도록 펼치기")
struct TreeExpansionModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let other: UUID
        let directory: URL
        var model: BoardBrowserModel { harness.model }

        func id(_ name: String) throws -> UUID {
            try #require(model.loadedSnapshot?.node(named: name)).id
        }
    }

    /// 최상위: 그룹 "Drafts", 웹 링크 "Site". "Drafts" 안: 그룹 "Data". 다른 Board "Other"가 있다. 처음에는 모두 접혀 있다.
    private func opened(_ directory: URL) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        var ids = (UUID(), UUID())
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "Board")
            let drafts = try #require(try await seed.service.apply(.addGroup(name: "Drafts", parentID: nil, position: nil), to: board).committed)
                .snapshot.node(named: "Drafts")?.id
            _ = try await seed.service.apply(.addGroup(name: "Data", parentID: drafts, position: nil), to: board)
            _ = try await seed.service.apply(.addWebLink(name: "Site", url: "https://example.com", parentID: nil, position: nil), to: board)
            ids = (board, try await makeBoard(seed, "Other"))
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, project: ids.0, other: ids.1, directory: directory)
    }

    @Test("선택한 그룹 안에 그룹을 추가하면 그 그룹이 펼쳐진다(재현: Drafts 다음 Data가 보이지 않음)")
    func addGroupIntoSelectedGroup() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let drafts = try o.id("Drafts")
            #expect(!o.model.isExpanded(drafts))
            o.model.selectedNodeID = drafts

            o.model.beginAddGroup()
            o.model.nodeForm?.name = "Notes"
            await o.model.confirmNodeForm()

            #expect(o.model.isExpanded(drafts))
            #expect(o.model.visibleNodeIDs.contains(try o.id("Notes")))
        }
    }

    @Test("깊은 그룹 안에 웹 링크를 추가하면 그 그룹과 모든 상위 그룹이 펼쳐진다")
    func addWebLinkIntoNestedGroup() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("Data")

            o.model.beginAddWebLink()
            o.model.nodeForm?.name = "Wiki"
            o.model.nodeForm?.url = "https://example.com/wiki"
            await o.model.confirmNodeForm()

            #expect(o.model.isExpanded(try o.id("Drafts")))
            #expect(o.model.isExpanded(try o.id("Data")))
            #expect(o.model.visibleNodeIDs.contains(try o.id("Wiki")))
        }
    }

    @Test("선택한 그룹 안에 Bishop을 추가하면 그 그룹이 펼쳐진다")
    func addBishopIntoGroup() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let drafts = try o.id("Drafts")
            o.model.selectedNodeID = drafts
            o.harness.picker.results = [[try TargetFiles.file(directory, "targets/note.md")]]

            await o.model.addBishops()

            #expect(o.model.isExpanded(drafts))
            #expect(o.model.visibleNodeIDs.contains(try o.id("note.md")))
        }
    }

    enum Move: String, CaseIterable, Sendable { case dialog, drop }

    @Test("항목을 접힌 그룹으로 옮기면 그 그룹과 상위 그룹이 펼쳐진다", arguments: Move.allCases)
    func moveIntoCollapsedGroup(way: Move) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let site = try o.id("Site"), data = try o.id("Data")
            switch way {
            case .dialog:
                o.model.selectedNodeID = site
                o.model.beginMove()
                await o.model.confirmMove(to: .group(data))
            case .drop:
                await o.model.dropNode(site, on: data)
            }

            #expect(o.model.isExpanded(try o.id("Drafts")))
            #expect(o.model.isExpanded(data))
            #expect(o.model.visibleNodeIDs.contains(site))
        }
    }

    @Test("최상위에 추가하면 펼침 상태가 바뀌지 않고, 사용자가 접은 그룹은 접힌 채로 남는다")
    func rootInsertAndUserCollapse() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let drafts = try o.id("Drafts")
            o.model.setExpanded(drafts, true)
            o.model.setExpanded(drafts, false)

            o.model.selectedNodeID = nil
            o.model.beginAddGroup()
            o.model.nodeForm?.name = "Top"
            await o.model.confirmNodeForm()

            #expect(!o.model.isExpanded(drafts))
            #expect(o.model.visibleNodeIDs.contains(try o.id("Top")))
            #expect(!o.model.visibleNodeIDs.contains(try o.id("Data")))
        }
    }

    @Test("다른 Board를 고르면 펼침 상태를 비운다")
    func boardSwitchResets() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let drafts = try o.id("Drafts")
            o.model.setExpanded(drafts, true)

            await o.model.select(o.other)
            await o.model.select(o.project)

            #expect(!o.model.isExpanded(drafts))
        }
    }
}
