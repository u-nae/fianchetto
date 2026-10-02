import Foundation
import SwiftData
import Testing
@testable import Fianchetto

@Suite("구성 변경 커밋 서비스 (W05)")
struct ConfigurationServiceTests {
    // MARK: Board 만들기

    @Test("[W05-create-board-first-revision] Board를 만들면 빈 초기 구성의 첫 revision이 기록된다", .tags(.A01))
    func createBoardRecordsFirstRevision() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)

            let outcome = try await harness.service.createProject(named: "  서비스 A ")

            let (summary, snapshot) = try #require(outcome.committed)
            #expect(summary.sequence == 1)
            #expect(summary.cause == .created)
            #expect(summary.recordedAt == date(0))
            #expect(summary.projectName == "서비스 A")
            #expect(snapshot == ConfigurationSnapshot(projectName: "서비스 A", nodes: []))
            let projects = try await harness.store.projects()
            #expect(projects.count == 1)
            let project = try #require(projects.first)
            #expect(project.id == summary.projectID)
            #expect(project.currentRevisionID == summary.id)
            #expect(project.createdAt == summary.recordedAt)
            #expect(project.archivedAt == nil && project.origin == nil)
            #expect(try await harness.store.revisionSummaries(projectID: project.id) == [summary])
            #expect(try await harness.store.currentSnapshot(projectID: project.id) == snapshot)
        }
    }

    @Test("[W05-create-board-no-filesystem-change] Board를 만들고 그룹을 추가해도 파일 시스템에 디렉토리나 파일이 생기지 않는다", .tags(.A01))
    func createBoardDoesNotTouchFileSystem() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let before = directoryListing(directory)

            let project = try await makeBoard(harness)
            let group = try #require(try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed)
            let groupID = try #require(group.snapshot.node(named: "개발")).id
            _ = try await harness.service.apply(.addGroup(name: "하위", parentID: groupID, position: nil), to: project)

            let after = directoryListing(directory)
            let storeFiles: Set<String> = ["Fianchetto.store", "Fianchetto.store-wal", "Fianchetto.store-shm"]
            #expect(after.directories == before.directories)
            #expect(after.files.subtracting(before.files).isSubset(of: storeFiles))
        }
    }

    @Test("[W05-create-board-blank-rejected] 빈 이름으로는 Board를 만들 수 없다")
    func blankBoardNameIsRejected() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)

            #expect(try await harness.service.createProject(named: "   ") == .rejected(.blankName))
            #expect(try await harness.store.projects().isEmpty)
        }
    }

    @Test("[W05-create-board-same-name-allowed] 같은 이름의 Board를 여러 개 만들 수 있다")
    func sameBoardNameIsAllowed() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)

            let first = try await makeBoard(harness)
            let second = try await makeBoard(harness)

            #expect(first != second)
            #expect(try await harness.store.projects().count == 2)
            #expect(try await harness.store.revisionSummaries(projectID: first).map(\.sequence) == [1])
            #expect(try await harness.store.revisionSummaries(projectID: second).map(\.sequence) == [1])
        }
    }

    // MARK: 커밋

    @Test("[W05-commit-revision-and-current] 변경을 확정하면 새 revision과 현재 구성이 함께 저장된다", .tags(.A01))
    func commitStoresRevisionAndCurrentTogether() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)

            let (summary, snapshot) = try #require(
                try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed
            )

            #expect(summary.sequence == 2)
            #expect(summary.cause == .edited(.addGroup))
            #expect(summary.recordedAt == date(1))
            #expect(snapshot.node(named: "개발")?.kind == .group)
            #expect(try await harness.store.currentSnapshot(projectID: project) == snapshot)
            let summaries = try await harness.store.revisionSummaries(projectID: project)
            try harness.reopened { store throws in
                #expect(try store.project(project)?.currentRevisionID == summary.id)
                #expect(try store.revisionSummaries(projectID: project) == summaries)
                #expect(try store.snapshot(revisionID: summaries[0].id).nodes.isEmpty)
            }
        }
    }

    @Test("[W05-commit-cause-per-edit] 편집 종류는 revision 원인으로 기록된다", arguments: RevisionCause.EditKind.allCases)
    func editKindIsRecordedAsCause(kind: RevisionCause.EditKind) async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let (project, ids) = try await seedLinkedBoard(harness)
            let (edit, access): (ConfigurationEdit, [Data]) = switch kind {
            case .renameProject: (.renameProject("서비스 B"), [])
            case .addGroup: (.addGroup(name: "문서", parentID: nil, position: nil), [])
            case .addLinkedItems: (.addLinkedItems([LinkedTarget(displayName: "x", kind: .file, path: "/x")], parentID: ids.group, position: nil), [Data([1])])
            case .addWebLink: (.addWebLink(name: "링크", url: "https://example.com", parentID: nil, position: nil), [])
            case .renameNode: (.renameNode(ids.backend, "api"), [])
            case .changeURL: (.changeURL(ids.link, "https://example.com/v2"), [])
            case .move: (.move(ids.backend, toParent: nil, position: nil), [])
            case .remove: (.remove(ids.link), [])
            case .replaceTarget: (.replaceTarget(ids.backend, kind: .folder, path: "/dev/new-api", identity: .differentTarget), [Data([3])])
            }

            let outcome = try await harness.service.apply(edit, to: project, access: access)

            #expect(try #require(outcome.committed).summary.cause == .edited(kind))
        }
    }

    @Test("[W05-linked-items-save-references] 연결 대상 추가는 새 참조 레코드를 revision과 함께 저장한다")
    func linkedItemsSaveReferences() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            let group = try await addGroup(harness, project, "개발")
            let targets = [
                LinkedTarget(displayName: "assets", kind: .folder, path: "/design/assets"),
                LinkedTarget(displayName: "meeting.md", kind: .file, path: "/notes/meeting.md"),
            ]

            let (_, snapshot) = try #require(try await harness.service.apply(
                .addLinkedItems(targets, parentID: group, position: nil), to: project, access: [Data([0xB1]), Data([0xB2])]
            ).committed)

            let assets = try #require(snapshot.node(named: "assets")?.referenceID)
            let meeting = try #require(snapshot.node(named: "meeting.md")?.referenceID)
            #expect(try await harness.store.reference(assets) == ResourceReferenceRecord(
                id: assets, initialPath: "/design/assets", kind: .folder, bookmarkData: Data([0xB1]), lastResolvedPath: "/design/assets"
            ))
            #expect(try await harness.store.reference(meeting) == ResourceReferenceRecord(
                id: meeting, initialPath: "/notes/meeting.md", kind: .file, bookmarkData: Data([0xB2]), lastResolvedPath: "/notes/meeting.md"
            ))
            for referenceID in snapshot.nodes.compactMap(\.referenceID) {
                #expect(try await harness.store.reference(referenceID) != nil)
            }
        }
    }

    @Test("[W05-replace-target-saves-reference] 대상 교체는 새 참조 레코드를 저장하고 이전 참조 레코드는 그대로 둔다")
    func replaceTargetSavesReference() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let (project, ids) = try await seedLinkedBoard(harness)
            let before = try #require(try await harness.store.reference(ids.backendReference))

            let (_, snapshot) = try #require(try await harness.service.apply(
                .replaceTarget(ids.backend, kind: .folder, path: "/dev/new-api", identity: .differentTarget),
                to: project, access: [Data([0xB3])]
            ).committed)

            let newReference = try #require(snapshot.node(ids.backend)?.referenceID)
            #expect(newReference != ids.backendReference)
            let saved = try #require(try await harness.store.reference(newReference))
            #expect(saved.initialPath == "/dev/new-api")
            #expect(saved.bookmarkData == Data([0xB3]))
            #expect(try await harness.store.reference(ids.backendReference) == before)
        }
    }

    @Test("[W05-same-target-no-reference] 같은 대상을 다시 고른 교체는 참조 레코드도 만들지 않는다")
    func sameTargetCreatesNoReference() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let (project, ids) = try await seedLinkedBoard(harness)
            let count = try await harness.store.referenceCount()

            let outcome = try await harness.service.apply(
                .replaceTarget(ids.backend, kind: .folder, path: "/dev/legacy-api", identity: .sameTarget),
                to: project, access: [Data([0xB4])]
            )

            #expect(outcome == .unchanged)
            #expect(try await harness.store.referenceCount() == count)
        }
    }

    @Test("[W05-linked-items-failure-rolls-back-references] 연결 대상 추가의 저장이 실패하면 Node·revision·참조 레코드가 모두 남지 않는다", .tags(.A13))
    func linkedItemsFailureRollsBackReferences() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            let group = try await addGroup(harness, project, "개발")
            let state = try await currentState(harness, project)
            harness.fault.failNext()

            await #expect(throws: ConfigurationServiceError.saveFailed) {
                try await harness.service.apply(
                    .addLinkedItems([LinkedTarget(displayName: "assets", kind: .folder, path: "/design/assets")], parentID: group, position: nil),
                    to: project, access: [Data([0xB1])]
                )
            }

            #expect(try await currentState(harness, project) == state)
            try harness.reopened { store throws in
                #expect(try store.project(project)?.currentRevisionID == state.current)
                #expect(try store.revisionSummaries(projectID: project).count == state.revisions)
                #expect(try store.context.fetchCount(FetchDescriptor<SchemaV1.ResourceReferenceModel>()) == state.references)
            }
        }
    }

    @Test("[W05-access-mismatch-rejected] 북마크 바이트 수가 대상 수와 맞지 않는 요청은 거부한다", arguments: [0, 1, 2])
    func accessMismatchIsRejected(caseIndex: Int) async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let (project, ids) = try await seedLinkedBoard(harness)
            let state = try await currentState(harness, project)
            let request: (ConfigurationEdit, [Data]) = switch caseIndex {
            case 0: (.addLinkedItems([
                    LinkedTarget(displayName: "a", kind: .file, path: "/a"), LinkedTarget(displayName: "b", kind: .file, path: "/b"),
                ], parentID: ids.group, position: nil), [Data([1])])
            case 1: (.replaceTarget(ids.backend, kind: .folder, path: "/dev/new-api", identity: .differentTarget), [])
            default: (.addGroup(name: "문서", parentID: nil, position: nil), [Data([1])])
            }

            let outcome = try await harness.service.apply(request.0, to: project, access: request.1)

            #expect(outcome == .rejected(.accessMismatch))
            #expect(try await currentState(harness, project) == state)
        }
    }

    @Test("[W05-unchanged-not-saved] 무변경 결과는 저장하지 않는다")
    func unchangedIsNotSaved() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            _ = try await addGroup(harness, project, "개발")
            let state = try await currentState(harness, project)

            #expect(try await harness.service.apply(.renameProject(" 서비스 A "), to: project) == .unchanged)
            #expect(try await currentState(harness, project) == state)
        }
    }

    @Test("[W05-rejected-not-saved] 거부된 편집은 저장하지 않는다")
    func rejectedIsNotSaved() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            let state = try await currentState(harness, project)

            #expect(try await harness.service.apply(.renameNode(fixedID(404), "api"), to: project) == .rejected(.edit(.nodeNotFound)))
            #expect(try await currentState(harness, project) == state)
        }
    }

    @Test("[W05-archived-rejected] 보관된 Board의 구성은 바꿀 수 없다", arguments: [
        ConfigurationEdit.addGroup(name: "개발", parentID: nil, position: nil),
        .renameProject("서비스 A"),
    ])
    func archivedBoardIsRejected(edit: ConfigurationEdit) async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            try await harness.store.setArchived(project, at: date(100))
            let state = try await currentState(harness, project)

            #expect(try await harness.service.apply(edit, to: project) == .rejected(.archived))
            #expect(try await currentState(harness, project) == state)
        }
    }

    @Test("[W05-archived-before-edit-reason] 보관된 Board의 거부 사유는 편집 자체의 사유보다 먼저다")
    func archivedComesBeforeEditReason() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            try await harness.store.setArchived(project, at: date(100))

            #expect(try await harness.service.apply(.renameNode(fixedID(404), "api"), to: project) == .rejected(.archived))
            #expect(try await harness.service.apply(
                .addGroup(name: "개발", parentID: nil, position: nil), to: project, access: [Data([1])]
            ) == .rejected(.archived))
        }
    }

    @Test("[W05-missing-project-rejected] 없는 Board는 바꿀 수 없다")
    func missingProjectIsRejected() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            let state = try await currentState(harness, project)

            #expect(try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: fixedID(404)) == .rejected(.projectNotFound))
            #expect(try await harness.store.projects().count == 1)
            #expect(try await currentState(harness, project) == state)
        }
    }

    @Test("[W05-unreadable-current-errors] 현재 구성을 읽을 수 없으면 오류를 내고 빈 구성으로 대신하지 않는다")
    func unreadableCurrentConfigurationErrors() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let seedDirectory = directory.appending(path: "seed")
            let seed = try ServiceHarness(directory: seedDirectory)
            let project = try await makeBoard(seed)
            let corrupted = directory.appending(path: "corrupted/Fianchetto.store")
            try copyStoreFiles(from: seed.url, to: corrupted)
            try withStore(at: corrupted) { store in
                let model = try #require(try store.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>()).first)
                model.snapshotData = Data("{\"schemaVersion\":1,".utf8)
                try store.save()
            }
            let testedDirectory = directory.appending(path: "tested")
            try copyStoreFiles(from: corrupted, to: testedDirectory.appending(path: "Fianchetto.store"))
            let harness = try ServiceHarness(directory: testedDirectory)

            await #expect(throws: ConfigurationServiceError.currentConfigurationUnreadable) {
                try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project)
            }
            #expect(try await harness.store.revisionSummaries(projectID: project).map(\.sequence) == [1])
        }
    }

    // MARK: 저장 실패 (A13)

    @Test("[W05-save-failure-rolls-back] 저장이 실패하면 오류를 돌려주고 새 revision과 현재 구성 변경이 모두 남지 않는다", .tags(.A13))
    func saveFailureRollsBack() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            let state = try await currentState(harness, project)
            let current = try await harness.store.currentSnapshot(projectID: project)
            harness.fault.failNext()

            await #expect(throws: ConfigurationServiceError.saveFailed) {
                try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project)
            }

            #expect(try await currentState(harness, project) == state)
            #expect(try await harness.store.currentSnapshot(projectID: project) == current)
            try harness.reopened { store throws in
                #expect(try store.project(project)?.currentRevisionID == state.current)
                #expect(try store.revisionSummaries(projectID: project).count == state.revisions)
            }
        }
    }

    @Test("[W05-retry-after-failure] 저장 실패 뒤 같은 편집을 다시 보내면 한 번만 기록된다", .tags(.A13))
    func retryAfterFailureRecordsOnce() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            let edit = ConfigurationEdit.addGroup(name: "개발", parentID: nil, position: nil)
            harness.fault.failNext()
            _ = try? await harness.service.apply(edit, to: project)

            let (summary, snapshot) = try #require(try await harness.service.apply(edit, to: project).committed)

            #expect(summary.sequence == 2)
            #expect(snapshot.nodes.filter { $0.displayName == "개발" }.count == 1)
        }
    }

    @Test("[W05-sequence-after-failure] 저장 실패 뒤의 다음 변경은 순번을 건너뛰지 않는다", .tags(.A13))
    func sequenceContinuesAfterFailure() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            harness.fault.failNext()
            _ = try? await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project)

            let (summary, snapshot) = try #require(
                try await harness.service.apply(.addGroup(name: "문서", parentID: nil, position: nil), to: project).committed
            )

            #expect(summary.sequence == 2)
            #expect(snapshot.node(named: "문서") != nil)
            #expect(snapshot.node(named: "개발") == nil)
        }
    }

    @Test("[W05-create-board-failure-rolls-back] Board 만들기 중 저장이 실패하면 Project와 revision이 모두 남지 않는다", .tags(.A13))
    func createBoardFailureRollsBack() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            harness.fault.failNext()

            await #expect(throws: ConfigurationServiceError.saveFailed) { try await harness.service.createProject(named: "서비스 A") }
            #expect(try await harness.store.projects().isEmpty)

            let created = try await makeBoard(harness, "서비스 B")

            try harness.reopened { store throws in
                let projects = try store.projects()
                #expect(projects.map(\.id) == [created])
                #expect(try store.revisionSummaries(projectID: created).map(\.projectName) == ["서비스 B"])
                #expect(try store.context.fetchCount(FetchDescriptor<SchemaV1.RevisionModel>()) == 1)
            }
        }
    }

    // MARK: 순서와 직렬화

    @Test("[W05-concurrent-commits-serialized] 같은 Board에 동시에 들어온 변경은 하나씩 커밋되어 순번이 연속된다")
    func concurrentCommitsAreSerialized() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            let service = harness.service

            let outcomes = try await withThrowingTaskGroup(of: ConfigurationCommitOutcome.self) { group in
                for index in 1...20 {
                    group.addTask { try await service.apply(.addGroup(name: "그룹 \(index)", parentID: nil, position: nil), to: project) }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }

            #expect(outcomes.allSatisfy { $0.committed != nil })
            #expect(try await harness.store.revisionSummaries(projectID: project).map(\.sequence) == Array(1...21))
            let current = try await harness.store.currentSnapshot(projectID: project)
            #expect(Set(current.nodes.map(\.displayName)) == Set((1...20).map { "그룹 \($0)" }))
        }
    }

    @Test("[W05-sequence-independent-of-clock] 시계가 뒤로 가도 순번은 계속 증가한다")
    func sequenceIgnoresClockRegression() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory, clock: TestClock([date(10), date(5)]))
            let project = try await makeBoard(harness)

            let (summary, _) = try #require(try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed)

            #expect(summary.sequence == 2)
            #expect(summary.recordedAt == date(5))
            #expect(try await harness.store.revisionSummaries(projectID: project).map(\.sequence) == [1, 2])
        }
    }

    @Test("[W05-sequence-per-project] Board마다 순번을 따로 센다")
    func sequenceIsPerProject() async throws {
        try await withTemporaryDirectoryAsync { directory in
            let harness = try ServiceHarness(directory: directory)
            let a = try await makeBoard(harness, "서비스 A")
            let b = try await makeBoard(harness, "서비스 B")

            _ = try await addGroup(harness, a, "1")
            _ = try await addGroup(harness, a, "2")
            _ = try await addGroup(harness, b, "1")

            #expect(try await harness.store.revisionSummaries(projectID: a).last?.sequence == 3)
            #expect(try await harness.store.revisionSummaries(projectID: b).last?.sequence == 2)
        }
    }

    // MARK: 도우미

    struct StoreState: Equatable {
        var current: UUID
        var revisions: Int
        var references: Int
    }

    private func currentState(_ harness: ServiceHarness, _ project: UUID) async throws -> StoreState {
        let record = try #require(try await harness.store.projects().first { $0.id == project })
        return StoreState(
            current: record.currentRevisionID,
            revisions: try await harness.store.revisionSummaries(projectID: project).count,
            references: try await harness.store.referenceCount()
        )
    }

    private func addGroup(_ harness: ServiceHarness, _ project: UUID, _ name: String) async throws -> UUID {
        let committed = try #require(try await harness.service.apply(.addGroup(name: name, parentID: nil, position: nil), to: project).committed)
        return try #require(committed.snapshot.node(named: name)).id
    }

    struct LinkedIDs {
        var group: UUID
        var backend: UUID
        var backendReference: UUID
        var link: UUID
    }

    /// 그룹 "개발", 그 안의 연결 폴더 "backend", 최상위 웹 링크 "API 명세"가 있는 Board.
    private func seedLinkedBoard(_ harness: ServiceHarness) async throws -> (UUID, LinkedIDs) {
        let project = try await makeBoard(harness)
        let group = try await addGroup(harness, project, "개발")
        let linked = try #require(try await harness.service.apply(
            .addLinkedItems([LinkedTarget(displayName: "backend", kind: .folder, path: "/dev/legacy-api")], parentID: group, position: nil),
            to: project, access: [Data([0xB0])]
        ).committed)
        let backend = try #require(linked.snapshot.node(named: "backend"))
        let link = try #require(try await harness.service.apply(
            .addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil), to: project
        ).committed)
        let linkID = try #require(link.snapshot.node(named: "API 명세")).id
        return (project, LinkedIDs(group: group, backend: backend.id, backendReference: try #require(backend.referenceID), link: linkID))
    }

    private func directoryListing(_ directory: URL) -> (files: Set<String>, directories: Set<String>) {
        var files = Set<String>(), directories = Set<String>()
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = enumerator?.nextObject() as? URL {
            let relative = String(url.path.dropFirst(directory.path.count + 1))
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                directories.insert(relative)
            } else {
                files.insert(relative)
            }
        }
        return (files, directories)
    }
}
