import Foundation
import SwiftData
import Testing
@testable import Fianchetto

@MainActor
@Suite("기본 창과 Board 탐색 (W07)")
struct BoardBrowserModelTests {
    // MARK: 첫 실행과 Board 만들기

    @Test("[W07-first-launch-empty] 첫 실행에는 빈 Board 목록과 Board 만들기 동작을 보여 준다")
    func firstLaunchIsEmpty() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)

            await harness.model.start()

            #expect(harness.model.phase == .ready)
            #expect(harness.model.activeBoards.isEmpty && harness.model.archivedBoards.isEmpty)
            #expect(harness.model.selectedBoardID == nil)
            #expect(harness.model.current == .none)
            #expect(harness.model.canCreateBoard)
        }
    }

    @Test("[W07-create-board-selects] Board를 만들면 목록에 나타나고 선택되며 빈 현재 구성을 보여 준다", .tags(.A01))
    func createBoardSelectsIt() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            await harness.model.start()

            harness.model.beginCreate()
            harness.model.creation?.name = "서비스 A"
            await harness.model.confirmCreate()

            #expect(harness.model.activeNames == ["서비스 A"])
            let created = try #require(harness.model.board(named: "서비스 A"))
            #expect(harness.model.selectedBoardID == created.id)
            #expect(harness.model.loadedSnapshot == ConfigurationSnapshot(projectName: "서비스 A", nodes: []))
            #expect(harness.model.creation == nil)
            #expect(harness.lastBoard.lastBoardID == created.id)

            let reopened = BrowserHarness(directory: directory.appending(path: "reopened"), lastBoard: harness.lastBoard)
            try copyStoreFiles(from: harness.url, to: reopened.url)
            await reopened.model.start()
            #expect(reopened.model.activeNames == ["서비스 A"])
            #expect(reopened.model.loadedSnapshot?.nodes.isEmpty == true)
            let store = try #require(reopened.model.openedStore).store
            #expect(try await store.revisionSummaries(projectID: created.id).map(\.sequence) == [1])
        }
    }

    @Test("[W07-sidebar-create-entry] Board 목록 위의 \"Board 만들기\"에서도 만들기 입력 창을 연다")
    func createEntryWithExistingBoards() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            try await seedStore(in: directory, at: harness.url) { _ = try await makeBoard($0) }
            await harness.model.start()

            harness.model.beginCreate()

            #expect(harness.model.creation == BoardBrowserModel.Creation())
        }
    }

    @Test("[W07-cancel-saves-nothing] 만들기 입력 창을 취소하면 아무것도 저장하지 않는다")
    func cancelSavesNothing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            await harness.model.start()

            harness.model.beginCreate()
            harness.model.creation?.name = "서비스 A"
            harness.model.cancelCreate()

            #expect(harness.model.creation == nil)
            #expect(harness.model.activeBoards.isEmpty)
            #expect(try await harness.model.openedStore?.store.projects().isEmpty == true)
        }
    }

    @Test("[W07-single-confirm-while-saving] 저장 중에는 확정을 한 번만 받는다")
    func singleConfirmWhileSaving() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            await harness.model.start()
            harness.model.beginCreate()
            harness.model.creation?.name = "서비스 A"
            #expect(harness.model.canConfirmCreate)

            async let first: Void = harness.model.confirmCreate()
            async let second: Void = harness.model.confirmCreate()
            _ = await (first, second)

            #expect(try await harness.model.openedStore?.store.projects().count == 1)
            #expect(harness.model.activeNames == ["서비스 A"])
        }
    }

    enum CreateFailure: String, CaseIterable, Sendable { case blank, saveFailed }

    @Test("[W07-create-board-failure-keeps-input] Board를 만들지 못하면 입력을 유지하고 이유를 보여 준다", arguments: CreateFailure.allCases)
    func createFailureKeepsInput(failure: CreateFailure) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            await harness.model.start()
            let name = failure == .blank ? "   " : "서비스 A"
            if failure == .saveFailed { harness.fault.failNext() }

            harness.model.beginCreate()
            harness.model.creation?.name = name
            await harness.model.confirmCreate()

            let creation = try #require(harness.model.creation)
            #expect(creation.name == name)
            #expect(creation.message == (failure == .blank ? .nameRequired : .saveFailed))
            #expect(!creation.isSaving)
            #expect(harness.model.activeBoards.isEmpty)
            #expect(harness.model.selectedBoardID == nil)
        }
    }

    // MARK: 목록과 선택

    @Test("[W07-list-active-and-archived] Board 목록은 보관된 Board를 따로 모아 보여 준다")
    func listSeparatesArchived() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            try await seedStore(in: directory, at: harness.url) { seed in
                _ = try await makeBoard(seed, "서비스 A")
                _ = try await makeBoard(seed, "서비스 B")
                let old = try await makeBoard(seed, "옛 프로젝트")
                try await seed.store.setArchived(old, at: date(100))
            }

            await harness.model.start()

            #expect(harness.model.activeNames == ["서비스 A", "서비스 B"])
            #expect(harness.model.archivedNames == ["옛 프로젝트"])
            let archived = try #require(harness.model.archivedBoards.first)
            #expect(harness.model.statusText(for: archived) == "보관됨")
        }
    }

    @Test("[W07-same-name-distinguished] 같은 이름의 Board는 만든 시각으로 구분해 보여 준다")
    func sameNameBoardsAreDistinguished() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            try await seedStore(in: directory, at: harness.url) { seed in
                _ = try await makeBoard(seed, "서비스 A")
                _ = try await makeBoard(seed, "서비스 A")
            }

            await harness.model.start()

            let rows = harness.model.activeBoards
            #expect(rows.map(\.name) == ["서비스 A", "서비스 A"])
            #expect(harness.model.createdText(for: rows[0]) != harness.model.createdText(for: rows[1]))
        }
    }

    @Test("[W07-select-shows-tree] Board를 선택하면 현재 구성을 트리로 보여 준다")
    func selectShowsTree() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            try await seedStore(in: directory, at: harness.url) { try await seedServiceA($0) }
            await harness.model.start()
            let board = try #require(harness.model.board(named: "서비스 A"))

            await harness.model.select(board.id)

            let snapshot = try #require(harness.model.loadedSnapshot)
            #expect(harness.model.children(of: nil).map(\.displayName) == ["개발", "API 명세"])
            let development = try #require(snapshot.node(named: "개발"))
            #expect(harness.model.children(of: development.id).map(\.displayName) == ["설계 메모", "backend"])
            let backend = try #require(snapshot.node(named: "backend"))
            #expect(harness.model.childrenIfExpandable(backend) == nil)
            #expect(harness.model.kindText(for: development) == "그룹")
            #expect(harness.model.kindText(for: backend) == "Bishop")
            #expect(harness.model.kindText(for: try #require(snapshot.node(named: "API 명세"))) == "웹 링크")
        }
    }

    @Test("[W07-inspector-shows-node] 트리에서 항목을 선택하면 상세 영역에 표시 이름·종류·대상을 보여 준다")
    func inspectorShowsNode() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            try await seedStore(in: directory, at: harness.url) { try await seedServiceA($0) }
            await harness.model.start()
            await harness.model.select(try #require(harness.model.board(named: "서비스 A")).id)
            let snapshot = try #require(harness.model.loadedSnapshot)

            harness.model.selectedNodeID = try #require(snapshot.node(named: "backend")).id
            #expect(harness.model.inspector == NodeInspection(displayName: "backend", kind: "Bishop(폴더)", target: "/dev/legacy-api"))

            harness.model.selectedNodeID = try #require(snapshot.node(named: "API 명세")).id
            #expect(harness.model.inspector == NodeInspection(displayName: "API 명세", kind: "웹 링크", target: "https://example.com/api"))
        }
    }

    @Test("[W07-browsing-creates-no-revision] 열기·선택·복원은 revision을 만들지 않는다")
    func browsingCreatesNoRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let lastBoard = InMemoryLastBoard()
            let harness = BrowserHarness(directory: directory, lastBoard: lastBoard)
            try await seedStore(in: directory, at: harness.url) { seed in
                try await seedServiceA(seed)
                _ = try await makeBoard(seed, "서비스 B")
            }
            await harness.model.start()
            let store = try #require(harness.model.openedStore).store
            let before = try await revisionState(store)

            let a = try #require(harness.model.board(named: "서비스 A"))
            await harness.model.select(a.id)
            harness.model.selectedNodeID = harness.model.loadedSnapshot?.node(named: "개발")?.id
            await harness.model.select(try #require(harness.model.board(named: "서비스 B")).id)
            await harness.model.start()

            #expect(try await revisionState(store) == before)
        }
    }

    // MARK: 저장소를 연 뒤의 읽기 실패

    @Test("[W07-list-read-failure] Board 목록을 읽지 못하면 빈 목록 대신 오류와 다시 시도를 보여 준다")
    func listReadFailureShowsError() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            try await seedStore(in: directory, at: harness.url) { _ = try await makeBoard($0) }
            try withStore(at: harness.url) { store throws in
                store.context.insert(SchemaV1.ProjectModel(
                    id: fixedID(599), createdAt: date(5), currentRevisionID: fixedID(598), archivedAt: nil,
                    originKind: "fork", originProjectID: nil, originRevisionID: nil
                ))
                try store.save()
            }
            let tested = BrowserHarness(directory: directory.appending(path: "tested"))
            try copyStoreFiles(from: harness.url, to: tested.url)

            await tested.model.start()

            #expect(tested.model.phase == .listUnavailable)
            #expect(tested.model.activeBoards.isEmpty)
        }
    }

    @Test("[W07-current-read-failure] 선택한 Board의 현재 구성을 읽지 못하면 빈 구성 대신 오류를 보여 준다")
    func currentReadFailureShowsError() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let lastBoard = InMemoryLastBoard()
            let staging = directory.appending(path: "staging/Fianchetto.store")
            try await seedStore(in: directory, at: staging) { seed in
                _ = try await makeBoard(seed, "서비스 A")
                _ = try await makeBoard(seed, "서비스 B")
            }
            let corruptedID = try withStore(at: staging) { store throws -> UUID in
                let a = try #require(try store.projects().first)
                let model = try #require(try store.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>()).first { $0.id == a.currentRevisionID })
                model.snapshotData = Data("{".utf8)
                try store.save()
                return a.id
            }
            let harness = BrowserHarness(directory: directory.appending(path: "tested"), lastBoard: lastBoard)
            try copyStoreFiles(from: staging, to: harness.url)
            await harness.model.start()

            await harness.model.select(corruptedID)
            #expect(harness.model.current == .unreadable)
            #expect(harness.model.activeNames == ["서비스 A", "서비스 B"])

            await harness.model.select(try #require(harness.model.board(named: "서비스 B")).id)
            #expect(harness.model.loadedSnapshot?.projectName == "서비스 B")

            // 재실행 때 복원한 Board도 같은 오류를 보여 준다.
            lastBoard.lastBoardID = corruptedID
            let relaunched = BrowserHarness(directory: directory.appending(path: "relaunched"), lastBoard: lastBoard)
            try copyStoreFiles(from: harness.url, to: relaunched.url)
            await relaunched.model.start()
            #expect(relaunched.model.selectedBoardID == corruptedID)
            #expect(relaunched.model.current == .unreadable)
        }
    }

    // MARK: 마지막 Board 복원

    enum LastRecord: String, CaseIterable, Sendable { case active, archived, missing, none }

    @Test("[W07-restore-last-board] 다시 열면 마지막으로 본 Board를 현재 구성으로 연다", arguments: LastRecord.allCases)
    func restoresLastBoard(record: LastRecord) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let lastBoard = InMemoryLastBoard()
            let harness = BrowserHarness(directory: directory, lastBoard: lastBoard)
            var ids: [String: UUID] = [:]
            try await seedStore(in: directory, at: harness.url) { seed in
                ids["서비스 A"] = try await makeBoard(seed, "서비스 A")
                let old = try await makeBoard(seed, "옛 프로젝트")
                try await seed.store.setArchived(old, at: date(100))
                ids["옛 프로젝트"] = old
            }
            lastBoard.lastBoardID = switch record {
            case .active: ids["서비스 A"]
            case .archived: ids["옛 프로젝트"]
            case .missing: fixedID(404)
            case .none: nil
            }

            await harness.model.start()

            let expected: UUID? = switch record {
            case .active: ids["서비스 A"]
            case .archived: ids["옛 프로젝트"]
            case .missing, .none: nil
            }
            #expect(harness.model.selectedBoardID == expected)
            if let expected {
                let name = try #require(harness.model.board(named: record == .active ? "서비스 A" : "옛 프로젝트")).name
                #expect(harness.model.selectedBoardID == expected)
                #expect(harness.model.loadedSnapshot?.projectName == name)
            } else {
                #expect(harness.model.current == .none)
            }
        }
    }

    @Test("[W07-selection-recorded] Board를 선택하면 마지막 Board 기록을 바꾼다")
    func selectionIsRecorded() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            try await seedStore(in: directory, at: harness.url) { seed in
                _ = try await makeBoard(seed, "서비스 A")
                _ = try await makeBoard(seed, "서비스 B")
            }
            await harness.model.start()
            let b = try #require(harness.model.board(named: "서비스 B"))

            await harness.model.select(b.id)

            #expect(harness.lastBoard.lastBoardID == b.id)
        }
    }

    // MARK: 저장소를 열 수 없을 때

    @Test("[W07-store-failure-recovery-screen] 저장소를 열 수 없으면 원인과 복구 선택지를 보여 준다",
          arguments: [StoreOpenError.Category.damaged, .incompatible, .accessDenied, .unavailable])
    func storeFailureShowsRecovery(category: StoreOpenError.Category) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory, script: OpenScript([category]))

            await harness.model.start()

            #expect(harness.model.phase == .storeUnavailable(category))
            let message = harness.model.recoveryMessage(for: category)
            #expect(!message.isEmpty)
            if category == .incompatible { #expect(message.contains("수 있습니다")) }
            #expect(harness.model.activeBoards.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    @Test("[W07-store-failure-recovery-screen] 원인마다 안내 문구가 다르다")
    func recoveryMessagesDiffer() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let model = BrowserHarness(directory: directory).model
            let messages = [StoreOpenError.Category.damaged, .incompatible, .accessDenied, .unavailable].map(model.recoveryMessage(for:))
            #expect(Set(messages).count == 4)
        }
    }

    @Test("[W07-retry-opens-store] 다시 시도해 저장소가 열리면 Board 목록을 보여 준다")
    func retryOpensStore() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory, script: OpenScript([.accessDenied, nil]))
            try await seedStore(in: directory, at: harness.url) { _ = try await makeBoard($0) }
            await harness.model.start()

            await harness.model.retry()

            #expect(harness.model.phase == .ready)
            #expect(harness.model.activeNames == ["서비스 A"])
        }
    }

    @Test("[W07-retry-fails-again] 다시 시도가 또 실패하면 복구 화면을 새 원인으로 유지한다")
    func retryFailsAgain() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory, script: OpenScript([.accessDenied, .damaged]))
            await harness.model.start()

            await harness.model.retry()

            #expect(harness.model.phase == .storeUnavailable(.damaged))
            #expect(harness.script.calls == 2)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    @Test("[W07-create-disabled-on-recovery] 복구 화면에서는 Board 만들기 명령이 꺼져 있다")
    func createDisabledOnRecovery() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory, script: OpenScript([.damaged]))
            await harness.model.start()

            #expect(!harness.model.canCreateBoard)
            harness.model.beginCreate()
            #expect(harness.model.creation == nil)
        }
    }

    @Test("[W07-reveal-and-quit] Finder에서 보기와 종료는 해당 동작만 한다")
    func revealAndQuit() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory, script: OpenScript([.damaged]))
            await harness.model.start()

            #expect(harness.model.canRevealStore)
            harness.model.revealStore()
            #expect(harness.actions.revealed == [harness.url])
            #expect(harness.actions.quits == 0)
            harness.model.quit()
            #expect(harness.actions.quits == 1)
            #expect(harness.actions.revealed.count == 1)

            let unknown = BrowserHarness(directory: directory, storeKnown: false)
            await unknown.model.start()
            #expect(unknown.model.phase == .storeUnavailable(.unavailable))
            #expect(!unknown.model.canRevealStore)
            unknown.model.revealStore()
            #expect(unknown.actions.revealed.isEmpty)
        }
    }

    @Test("[W07-store-opened-off-main] 저장소는 MainActor 밖에서 연다")
    func storeOpensOffMain() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)

            await harness.model.start()

            #expect(harness.script.openedOnMainThread == [false])
        }
    }

    // MARK: 접근성

    @Test("[W07-accessibility-labels] 목록과 트리 행은 접근성 레이블로 이름과 상태·종류를 알린다")
    func accessibilityLabels() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            try await seedStore(in: directory, at: harness.url) { seed in
                try await seedServiceA(seed)
                let old = try await makeBoard(seed, "옛 프로젝트")
                try await seed.store.setArchived(old, at: date(100))
            }
            await harness.model.start()
            await harness.model.select(try #require(harness.model.board(named: "서비스 A")).id)
            let snapshot = try #require(harness.model.loadedSnapshot)

            let archived = try #require(harness.model.archivedBoards.first)
            #expect(harness.model.accessibilityLabel(for: archived).contains("옛 프로젝트"))
            #expect(harness.model.accessibilityLabel(for: archived).contains("보관됨"))
            for (name, kind) in [("개발", "그룹"), ("backend", "Bishop"), ("API 명세", "웹 링크")] {
                let label = harness.model.accessibilityLabel(for: try #require(snapshot.node(named: name)))
                #expect(label.contains(name) && label.contains(kind))
            }
        }
    }

    // MARK: 도우미

    /// 개발(그룹) 아래 설계 메모(파일, 0)·backend(폴더, 1), 최상위 API 명세(웹 링크).
    private func seedServiceA(_ seed: ServiceHarness) async throws {
        let project = try await makeBoard(seed, "서비스 A")
        let group = try #require(try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed)
        let groupID = try #require(group.snapshot.node(named: "개발")).id
        _ = try await seed.service.apply(
            .addLinkedItems([LinkedTarget(displayName: "backend", kind: .folder, path: "/dev/legacy-api")], parentID: groupID, position: nil),
            to: project, access: [Data([1])]
        )
        _ = try await seed.service.apply(
            .addLinkedItems([LinkedTarget(displayName: "설계 메모", kind: .file, path: "/docs/design.md")], parentID: groupID, position: 0),
            to: project, access: [Data([2])]
        )
        _ = try await seed.service.apply(.addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil), to: project)
    }

    private struct RevisionState: Equatable {
        var revisions: [UUID: Int]
        var current: [UUID: UUID]
    }

    private func revisionState(_ store: ProjectStore) async throws -> RevisionState {
        var state = RevisionState(revisions: [:], current: [:])
        for project in try await store.projects() {
            state.revisions[project.id] = try await store.revisionSummaries(projectID: project.id).count
            state.current[project.id] = project.currentRevisionID
        }
        return state
    }
}
