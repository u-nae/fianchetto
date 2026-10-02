import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("Board 이름 변경·보관 화면 (W10)")
struct BoardLifecycleModelTests {
    private func opened(_ directory: URL, archived: Bool = false) async throws -> (BrowserHarness, UUID, UUID) {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        var ids = (UUID(), UUID())
        try await seedStore(in: directory, at: harness.url) { seed in
            ids.0 = try await makeBoard(seed, "서비스 A")
            ids.1 = try await makeBoard(seed, "서비스 B")
            if archived { try await seed.store.setArchived(ids.0, at: date(100)) }
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return (harness, ids.0, ids.1)
    }

    private func revisions(_ harness: BrowserHarness, _ project: UUID) async throws -> [RevisionSummary] {
        try await harness.model.openedStore!.store.revisionSummaries(projectID: project)
    }

    // MARK: 이름 변경

    @Test("[W10-rename-records-revision] Board 이름을 바꾸면 revision이 남고 과거 revision은 옛 이름을 가진다", .tags(.A04))
    func renameRecordsRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, a, _) = try await opened(directory)

            harness.model.beginRename()
            #expect(harness.model.rename?.name == "서비스 A")
            harness.model.rename?.name = "  서비스 B "
            await harness.model.confirmRename()

            #expect(harness.model.rename == nil)
            let summaries = try await revisions(harness, a)
            #expect(summaries.last?.cause == .edited(.renameProject))
            #expect(summaries.map(\.projectName) == ["서비스 A", "서비스 B"])
            #expect(harness.model.activeBoards.first { $0.id == a }?.name == "서비스 B")
            #expect(harness.model.loadedSnapshot?.projectName == "서비스 B")
            #expect(harness.model.selectedBoardID == a)
        }
    }

    @Test("[W10-rename-unchanged-or-cancel] 같은 이름으로 확정하거나 취소하면 아무것도 기록하지 않는다", .tags(.A04), arguments: [true, false])
    func renameUnchangedOrCancel(confirmSame: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, a, _) = try await opened(directory)

            harness.model.beginRename()
            if confirmSame {
                harness.model.rename?.name = " 서비스 A "
                await harness.model.confirmRename()
            } else {
                harness.model.rename?.name = "서비스 B"
                harness.model.cancelRename()
            }

            #expect(harness.model.rename == nil)
            #expect(try await revisions(harness, a).count == 1)
            #expect(harness.model.activeBoards.first { $0.id == a }?.name == "서비스 A")
        }
    }

    @Test("[W10-rename-blank] 빈 이름은 입력을 유지하고 이름이 필요하다고 알린다")
    func renameBlank() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, a, _) = try await opened(directory)

            harness.model.beginRename()
            harness.model.rename?.name = "   "
            await harness.model.confirmRename()

            #expect(harness.model.rename?.name == "   ")
            #expect(harness.model.rename?.message == .nameRequired)
            #expect(try await revisions(harness, a).count == 1)
        }
    }

    @Test("[W10-rename-save-failure] 이름 변경 저장이 실패하면 입력을 유지하고 저장하지 못했다고 알린다")
    func renameSaveFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, a, _) = try await opened(directory)
            harness.fault.failNext()

            harness.model.beginRename()
            harness.model.rename?.name = "서비스 B"
            await harness.model.confirmRename()

            #expect(harness.model.rename?.name == "서비스 B")
            #expect(harness.model.rename?.message == .saveFailed)
            #expect(harness.model.activeBoards.first { $0.id == a }?.name == "서비스 A")
            #expect(try await revisions(harness, a).count == 1)
        }
    }

    // MARK: 보관과 보관 해제

    @Test("[W10-archive-no-revision] Board를 보관하면 revision 없이 보관된 Board로 옮겨지고 읽기 전용이 된다")
    func archiveMovesBoard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, a, _) = try await opened(directory)
            let before = try await revisions(harness, a)

            await harness.model.archiveSelected()

            #expect(try await revisions(harness, a) == before)
            #expect(harness.model.archivedBoards.map(\.id) == [a])
            #expect(harness.model.activeNames == ["서비스 B"])
            #expect(harness.model.selectedBoardID == a)
            #expect(harness.model.loadedSnapshot != nil)
            #expect(harness.model.readOnlyText == "보관된 Board · 읽기 전용")
            #expect(!harness.model.canArchiveSelected && harness.model.canUnarchiveSelected)
        }
    }

    @Test("[W10-unarchive-no-revision] 보관을 해제하면 revision 없이 Board 목록의 원래 순서로 돌아오고 다시 바꿀 수 있다")
    func unarchiveRestoresBoard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, a, _) = try await opened(directory, archived: true)
            let before = try await revisions(harness, a)

            await harness.model.unarchiveSelected()

            #expect(try await revisions(harness, a) == before)
            #expect(harness.model.activeNames == ["서비스 A", "서비스 B"])
            #expect(harness.model.readOnlyText == nil)
            harness.model.beginRename()
            #expect(harness.model.rename != nil)
        }
    }

    enum Edit: String, CaseIterable, Sendable { case rename, addBishop, replaceTarget }

    @Test("[W10-archived-blocks-edits] 보관된 Board에서는 바꾸는 동작이 아무것도 기록하지 않고 안내한다", arguments: Edit.allCases)
    func archivedBlocksEdits(edit: Edit) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory.appending(path: "browser"))
            let legacy = try TargetFiles.folder(directory, "targets/legacy-api")
            var ids = (UUID(), UUID())
            try await seedStore(in: directory, at: harness.url) { seed in
                ids.0 = try await makeBoard(seed, "옛 프로젝트")
                let linked = try #require(try await seed.linking.link(LinkRequest(projectID: ids.0, parentID: nil, position: nil, urls: [legacy])).committed)
                ids.1 = try #require(linked.snapshot.node(named: "legacy-api")).id
                try await seed.store.setArchived(ids.0, at: date(100))
            }
            await harness.model.start()
            await harness.model.select(ids.0)
            harness.model.selectedNodeID = ids.1
            harness.picker.results = [[try TargetFiles.file(directory, "targets/x.md")]]
            harness.picker.replacementResults = [try TargetFiles.folder(directory, "targets/new-api")]
            let before = try await revisions(harness, ids.0)

            switch edit {
            case .rename: harness.model.beginRename()
            case .addBishop: await harness.model.addBishops()
            case .replaceTarget: await harness.model.beginReplaceTarget()
            }

            #expect(harness.model.linkNotice?.kind == .archived)
            #expect(harness.model.rename == nil)
            #expect(harness.picker.calls == 0 && harness.picker.replacementKinds.isEmpty)
            #expect(try await revisions(harness, ids.0) == before)
        }
    }

    @Test("[W10-archived-blocks-edits] 보관된 Board를 선택한 채로도 Board 만들기는 된다")
    func createBoardWhileArchivedSelected() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, _, _) = try await opened(directory, archived: true)

            harness.model.beginCreate()
            harness.model.creation?.name = "새 Board"
            await harness.model.confirmCreate()

            #expect(harness.model.activeNames.contains("새 Board"))
        }
    }

    @Test("[W10-archive-save-failure] 보관·보관 해제 저장이 실패하면 상태가 그대로이고 저장하지 못했다고 알린다", arguments: [true, false])
    func archiveSaveFailure(archiving: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, a, _) = try await opened(directory, archived: !archiving)
            harness.fault.failNext()

            if archiving { await harness.model.archiveSelected() } else { await harness.model.unarchiveSelected() }

            #expect(harness.model.linkNotice?.kind == .saveFailed)
            #expect((harness.model.board(named: "서비스 A")?.archivedAt != nil) == !archiving)
            #expect((try await harness.model.openedStore!.store.project(a)?.archivedAt != nil) == !archiving)
        }
    }

    @Test("[W10-commands-no-delete] 상태에 맞지 않거나 Board가 없으면 보관 명령은 아무 일도 하지 않는다")
    func commandsFollowState() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let (harness, a, _) = try await opened(directory)
            #expect(harness.model.canArchiveSelected && !harness.model.canUnarchiveSelected)

            await harness.model.unarchiveSelected()
            #expect(harness.model.linkNotice == nil)
            #expect(try await harness.model.openedStore!.store.project(a)?.archivedAt == nil)

            let empty = BrowserHarness(directory: directory.appending(path: "empty"))
            await empty.model.start()
            await empty.model.archiveSelected()
            empty.model.beginRename()
            #expect(empty.model.rename == nil && empty.model.linkNotice == nil)
            #expect(!empty.model.canArchiveSelected && !empty.model.canUnarchiveSelected)
        }
    }
}
