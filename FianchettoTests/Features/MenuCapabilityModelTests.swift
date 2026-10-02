import Foundation
import Testing
@testable import Fianchetto

/// 메뉴 켜짐 상태에 쓰는 판단 값. 각 값은 해당 동작이 실제로 창을 열거나 기록하는 조건과 같아야 한다.
/// (켜진 메뉴가 아무 일도 하지 않거나, 꺼진 메뉴의 동작이 실제로는 가능한 일이 없게 한다.)
@MainActor
@Suite("메뉴 켜짐 판단 값")
struct MenuCapabilityModelTests {
    enum Situation: String, CaseIterable, Sendable {
        case noBoard, noSelection, firstWing, lastWebLink, middleBishop, archivedBishop
    }

    struct Expected: Equatable {
        var addToBoard: Bool
        var renameNode: Bool
        var changeURL: Bool
        var moveUp: Bool
        var moveDown: Bool
        var move: Bool
        var remove: Bool
        var refresh: Bool
        var renameBoard: Bool
    }

    /// 최상위: Wing "개발"(0), Bishop 파일 "memo.md"(1), 웹 링크 "API 명세"(2).
    static func expected(_ situation: Situation) -> Expected {
        switch situation {
        case .noBoard:
            Expected(addToBoard: false, renameNode: false, changeURL: false, moveUp: false, moveDown: false, move: false, remove: false, refresh: false, renameBoard: false)
        case .noSelection:
            Expected(addToBoard: true, renameNode: false, changeURL: false, moveUp: false, moveDown: false, move: false, remove: false, refresh: true, renameBoard: true)
        case .firstWing:
            Expected(addToBoard: true, renameNode: true, changeURL: false, moveUp: false, moveDown: true, move: true, remove: true, refresh: true, renameBoard: true)
        case .lastWebLink:
            Expected(addToBoard: true, renameNode: true, changeURL: true, moveUp: true, moveDown: false, move: true, remove: true, refresh: true, renameBoard: true)
        case .middleBishop:
            Expected(addToBoard: true, renameNode: true, changeURL: false, moveUp: true, moveDown: true, move: true, remove: true, refresh: true, renameBoard: true)
        case .archivedBishop:
            Expected(addToBoard: false, renameNode: false, changeURL: false, moveUp: false, moveDown: false, move: false, remove: false, refresh: true, renameBoard: false)
        }
    }

    private func opened(_ directory: URL, _ situation: Situation) async throws -> (BrowserHarness, UUID) {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let memo = try TargetFiles.file(directory, "targets/memo.md")
        var project = UUID()
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "Board")
            _ = try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board)
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [memo]))
            _ = try await seed.service.apply(.addWebLink(name: "API 명세", url: "https://example.com", parentID: nil, position: nil), to: board)
            if situation == .archivedBishop { try await seed.store.setArchived(board, at: date(100)) }
            project = board
        }
        await harness.model.start()
        if situation != .noBoard { await harness.model.select(project) }
        let name: String? = switch situation {
        case .noBoard, .noSelection: nil
        case .firstWing: "개발"
        case .lastWebLink: "API 명세"
        case .middleBishop, .archivedBishop: "memo.md"
        }
        if let name { harness.model.selectedNodeID = try #require(harness.model.loadedSnapshot?.node(named: name)).id }
        return (harness, project)
    }

    @Test("판단 값은 상황별 기대값과 같다", arguments: Situation.allCases)
    func values(situation: Situation) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, _) = try await opened(directory, situation)
            let m = harness.model
            let actual = Expected(
                addToBoard: m.canAddToBoard, renameNode: m.canRenameSelectedNode, changeURL: m.canChangeURLOfSelected,
                moveUp: m.canMoveSelectedUp, moveDown: m.canMoveSelectedDown, move: m.canMoveSelected,
                remove: m.canRemoveSelected, refresh: m.canRefreshStatuses, renameBoard: m.canRenameSelectedBoard
            )
            #expect(actual == Self.expected(situation))
        }
    }

    enum Action: String, CaseIterable, Sendable {
        case addGroup, addWebLink, renameNode, changeURL, move, remove, renameBoard, moveUp, moveDown
    }

    /// 판단 값이 참이면 동작이 창을 열거나 revision을 남기고, 거짓이면 어느 쪽도 하지 않는다.
    @Test("판단 값이 참일 때만 동작이 창을 열거나 기록한다", arguments: Situation.allCases, Action.allCases)
    func matchesAction(situation: Situation, action: Action) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, project) = try await opened(directory, situation)
            let m = harness.model
            let revisions = { () async throws -> Int in try await m.openedStore!.store.revisionSummaries(projectID: project).count }
            let before = try await revisions()
            let capability: Bool
            let did: Bool
            switch action {
            case .addGroup:
                capability = m.canAddToBoard
                m.beginAddGroup()
                did = m.nodeForm != nil
            case .addWebLink:
                capability = m.canAddToBoard
                m.beginAddWebLink()
                did = m.nodeForm != nil
            case .renameNode:
                capability = m.canRenameSelectedNode
                m.beginRenameNode()
                did = m.nodeForm != nil
            case .changeURL:
                capability = m.canChangeURLOfSelected
                m.beginChangeURL()
                did = m.nodeForm != nil
            case .move:
                capability = m.canMoveSelected
                m.beginMove()
                did = m.moveDialog != nil
            case .remove:
                capability = m.canRemoveSelected
                m.beginRemove()
                did = m.removal != nil
            case .renameBoard:
                capability = m.canRenameSelectedBoard
                m.beginRename()
                did = m.rename != nil
            case .moveUp:
                capability = m.canMoveSelectedUp
                await m.moveSelectedUp()
                did = try await revisions() == before + 1
            case .moveDown:
                capability = m.canMoveSelectedDown
                await m.moveSelectedDown()
                did = try await revisions() == before + 1
            }
            #expect(capability == did)
        }
    }

    @Test("상태 새로고침 판단 값은 Board가 있을 때만 참이고, 보관된 Board에서도 참이다")
    func refreshCapability() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, _) = try await opened(directory, .archivedBishop)
            #expect(harness.model.canRefreshStatuses)
            await harness.model.refreshStatuses()
            #expect(!harness.bookmarks.scopedResolutions.isEmpty)
        }
    }
}
