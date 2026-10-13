import Foundation
import SwiftData
import Testing
@testable import Fianchetto

@Suite("과거 구성으로 복원 서비스 (W20)")
struct RestoreServiceTests {
    // MARK: 결정표 (spec-brief §4 restore_request_outcome, 32칸)

    enum Outcome: String, Sendable {
        case rejectedArchived, rejectedRevisionNotFound, errorTargetUnreadable, errorCurrentUnreadable, unchanged, restored
    }

    enum Target: String, Sendable { case found, notFound, otherBoard, unreadable }

    struct Cell: Sendable, CustomTestStringConvertible {
        var rule: String
        var archived: Bool
        var target: Target
        var currentReadable: Bool
        var same: Bool
        var expected: Outcome

        var testDescription: String {
            "\(rule) archived=\(archived) target=\(target.rawValue) currentReadable=\(currentReadable) same=\(same) -> \(expected.rawValue)"
        }
    }

    static let cells: [Cell] = [
        Cell(rule: "R1", archived: true, target: .found, currentReadable: true, same: true, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .found, currentReadable: true, same: false, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .found, currentReadable: false, same: true, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .found, currentReadable: false, same: false, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .notFound, currentReadable: true, same: true, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .notFound, currentReadable: true, same: false, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .notFound, currentReadable: false, same: true, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .notFound, currentReadable: false, same: false, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .otherBoard, currentReadable: true, same: true, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .otherBoard, currentReadable: true, same: false, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .otherBoard, currentReadable: false, same: true, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .otherBoard, currentReadable: false, same: false, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .unreadable, currentReadable: true, same: true, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .unreadable, currentReadable: true, same: false, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .unreadable, currentReadable: false, same: true, expected: .rejectedArchived),
        Cell(rule: "R1", archived: true, target: .unreadable, currentReadable: false, same: false, expected: .rejectedArchived),
        Cell(rule: "R2", archived: false, target: .notFound, currentReadable: true, same: true, expected: .rejectedRevisionNotFound),
        Cell(rule: "R2", archived: false, target: .notFound, currentReadable: true, same: false, expected: .rejectedRevisionNotFound),
        Cell(rule: "R2", archived: false, target: .notFound, currentReadable: false, same: true, expected: .rejectedRevisionNotFound),
        Cell(rule: "R2", archived: false, target: .notFound, currentReadable: false, same: false, expected: .rejectedRevisionNotFound),
        Cell(rule: "R2", archived: false, target: .otherBoard, currentReadable: true, same: true, expected: .rejectedRevisionNotFound),
        Cell(rule: "R2", archived: false, target: .otherBoard, currentReadable: true, same: false, expected: .rejectedRevisionNotFound),
        Cell(rule: "R2", archived: false, target: .otherBoard, currentReadable: false, same: true, expected: .rejectedRevisionNotFound),
        Cell(rule: "R2", archived: false, target: .otherBoard, currentReadable: false, same: false, expected: .rejectedRevisionNotFound),
        Cell(rule: "R3", archived: false, target: .unreadable, currentReadable: true, same: true, expected: .errorTargetUnreadable),
        Cell(rule: "R3", archived: false, target: .unreadable, currentReadable: true, same: false, expected: .errorTargetUnreadable),
        Cell(rule: "R3", archived: false, target: .unreadable, currentReadable: false, same: true, expected: .errorTargetUnreadable),
        Cell(rule: "R3", archived: false, target: .unreadable, currentReadable: false, same: false, expected: .errorTargetUnreadable),
        Cell(rule: "R4", archived: false, target: .found, currentReadable: false, same: true, expected: .errorCurrentUnreadable),
        Cell(rule: "R4", archived: false, target: .found, currentReadable: false, same: false, expected: .errorCurrentUnreadable),
        Cell(rule: "R5", archived: false, target: .found, currentReadable: true, same: true, expected: .unchanged),
        Cell(rule: "R6", archived: false, target: .found, currentReadable: true, same: false, expected: .restored),
    ]

    static let projectID = fixedID(10)
    static let targetSummary = RevisionSummary(
        id: fixedID(21), projectID: projectID, sequence: 2, recordedAt: date(20), cause: .created, projectName: "대상"
    )
    static let targetSnapshot = ConfigurationSnapshot(
        projectName: "대상", nodes: [ConfigurationNode(id: fixedID(31), kind: .group, displayName: "개발", parentID: nil, sortIndex: 0)]
    )
    static let otherSnapshot = ConfigurationSnapshot(projectName: "현재", nodes: [])

    static func state(_ cell: Cell) -> ProjectState {
        let restoreTarget: RestoreTarget = switch cell.target {
        case .found: .found(targetSummary, targetSnapshot)
        case .notFound: .notFound
        case .otherBoard: .otherProject
        case .unreadable: .unreadable
        }
        return ProjectState(
            project: ProjectRecord(
                id: projectID, createdAt: date(0), currentRevisionID: fixedID(22),
                archivedAt: cell.archived ? date(5) : nil, origin: nil
            ),
            latestSequence: 5,
            current: cell.currentReadable
                ? .success(cell.same ? targetSnapshot : otherSnapshot)
                : .failure(.damagedRecord(fixedID(22))),
            restoreTarget: restoreTarget
        )
    }

    /// 판정을 결과 종류로 바꾼다. restored면 추가될 revision의 출처·스냅샷·참조도 함께 단언한다.
    static func classify(_ decision: AppendDecision<ConfigurationService.Decision>) -> Outcome {
        switch decision {
        case let .append(append):
            #expect(append.cause == .restored(from: targetSummary.id))
            #expect(append.snapshot == targetSnapshot)
            #expect(append.references.isEmpty)
            return .restored
        case .skip(.outcome(.rejected(.archived))): return .rejectedArchived
        case .skip(.outcome(.rejected(.revisionNotFound))): return .rejectedRevisionNotFound
        case .skip(.outcome(.unchanged)): return .unchanged
        case .skip(.unreadableTarget): return .errorTargetUnreadable
        case .skip(.unreadableCurrent): return .errorCurrentUnreadable
        case .skip(.outcome): return .restored // 결정표에 없는 결과. 기댓값과 달라 실패한다.
        }
    }

    static func decide(_ cell: Cell) -> AppendDecision<ConfigurationService.Decision> {
        ConfigurationService.decideRestore(state: state(cell), now: { date(99) }, makeID: { fixedID(77) })
    }

    private func check(_ cell: Cell) {
        #expect(Self.classify(Self.decide(cell)) == cell.expected)
    }

    @Test("[W20-restore_request_outcome-R1] 보관된 Board는 대상·현재 상태와 무관하게 거부한다", arguments: cells.filter { $0.rule == "R1" })
    func archivedRejects(cell: Cell) { check(cell) }

    @Test("[W20-restore_request_outcome-R2] 대상 revision이 없거나 다른 Board면 거부한다", arguments: cells.filter { $0.rule == "R2" })
    func missingTargetRejects(cell: Cell) { check(cell) }

    @Test("[W20-restore_request_outcome-R3] 대상 revision의 구성을 읽을 수 없으면 대상 읽기 오류다", arguments: cells.filter { $0.rule == "R3" })
    func unreadableTargetErrors(cell: Cell) { check(cell) }

    @Test("[W20-restore_request_outcome-R4] 현재 구성을 읽을 수 없으면 현재 읽기 오류다", arguments: cells.filter { $0.rule == "R4" })
    func unreadableCurrentErrors(cell: Cell) { check(cell) }

    @Test("[W20-restore_request_outcome-R5] 대상이 현재와 같으면 revision을 만들지 않는다", arguments: cells.filter { $0.rule == "R5" })
    func sameCreatesNothing(cell: Cell) { check(cell) }

    @Test("[W20-restore_request_outcome-R6] 대상이 현재와 다르면 출처가 기록된 restored revision을 만든다", arguments: cells.filter { $0.rule == "R6" })
    func differentRestores(cell: Cell) { check(cell) }

    @Test("[W20-service-outcome-table] 판정은 결정표와 같고 restored일 때만 revision을 추가한다")
    func decisionTable() {
        #expect(Self.cells.count == 32)
        for cell in Self.cells {
            let decision = Self.decide(cell)
            #expect(Self.classify(decision) == cell.expected, "\(cell.testDescription)")
            if case .append = decision {
                #expect(cell.expected == .restored, "\(cell.testDescription)")
            } else {
                #expect(cell.expected != .restored, "\(cell.testDescription)")
            }
        }
        #expect(Self.cells.filter { $0.expected == .restored }.count == 1)
    }

    @Test("대상 정보 없이 호출된 판정은 대상 없음으로 거부한다")
    func missingTargetInformationRejects() {
        var state = Self.state(Cell(rule: "R6", archived: false, target: .found, currentReadable: true, same: false, expected: .restored))
        state.restoreTarget = nil
        let decision = ConfigurationService.decideRestore(state: state, now: { date(99) }, makeID: { fixedID(77) })
        #expect(Self.classify(decision) == .rejectedRevisionNotFound)
    }

    // MARK: 서비스 시나리오

    /// 복사한 저장소를 새 ID 번호대로 여는 서비스. seed가 쓴 번호와 겹치지 않는다.
    struct Seeded {
        let store: ProjectStore
        let service: ConfigurationService
        let fault: FaultPoint
        let project: UUID
        let other: UUID
        let ids: [Int: UUID]
        let url: URL
        private let copies = Counter()

        /// 지금까지 저장된 파일을 복사해 연 어댑터로 revision의 체크포인트 제목을 읽는다.
        func checkpointTitles(_ revisionID: UUID) throws -> [String] {
            let copy = url.deletingLastPathComponent().appending(path: "reopened-\(copies.next())/Fianchetto.store")
            try copyStoreFiles(from: url, to: copy)
            return try withStore(at: copy) { try $0.checkpoints(revisionID: revisionID).map(\.title) }
        }

        func revisionID(_ sequence: Int) -> UUID { ids[sequence]! }
        func summaries() async throws -> [RevisionSummary] { try await store.revisionSummaries(projectID: project) }
        func count() async throws -> Int { try await summaries().count }
        func snapshot(_ sequence: Int) async throws -> ConfigurationSnapshot { try await store.snapshot(revisionID: revisionID(sequence)) }
        func current() async throws -> ConfigurationSnapshot { try await store.currentSnapshot(projectID: project) }
        func currentRevisionID() async throws -> UUID? { try await store.project(project)?.currentRevisionID }
    }

    /// 1 Board 만들기("서비스 알파"), 2 Bishop backend(legacy, 참조 R1) 추가, 3 대상 교체(v2, 참조 R2), 4 Wing "문서", 5 이름 "서비스 A".
    /// `mutate`는 복사한 저장소 파일을 열어 손상이나 체크포인트를 더한다.
    private func seeded(
        _ directory: URL, mutate: (StoreAdapter, [Int: UUID]) throws -> Void = { _, _ in }
    ) async throws -> Seeded {
        let seed = try ServiceHarness(directory: directory.appending(path: "seed"))
        let legacy = try TargetFiles.folder(directory, "targets/legacy/backend")
        let v2 = try TargetFiles.folder(directory, "targets/v2/backend")
        let board = try await makeBoard(seed, "서비스 알파")
        _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [legacy]))
        let backend = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "backend")).id
        let replacement = TargetReplacementService(bookmarks: BookmarkAdapter(system: seed.bookmarks), configuration: seed.service)
        let preview = try await replacement.preview(projectID: board, nodeID: backend, newURL: v2).get()
        _ = try await replacement.confirm(preview)
        _ = try await seed.service.apply(.addGroup(name: "문서", parentID: nil, position: nil), to: board)
        _ = try await seed.service.apply(.renameProject("서비스 A"), to: board)
        let other = try await makeBoard(seed, "서비스 B")
        let summaries = try await seed.store.revisionSummaries(projectID: board)
        #expect(summaries.map(\.sequence) == [1, 2, 3, 4, 5])
        let ids = Dictionary(uniqueKeysWithValues: summaries.map { ($0.sequence, $0.id) })

        let destination = directory.appending(path: "tested/Fianchetto.store")
        try copyStoreFiles(from: seed.url, to: destination)
        try withStore(at: destination) { try mutate($0, ids) }

        let fault = FaultPoint()
        let store = ProjectStore(container: try StoreOpener.open(at: destination), beforeSave: { try fault.check() })
        let clock = TestClock(startingAt: date(1000)), generator = TestIDs(startingAt: 30001)
        let service = ConfigurationService(store: store, now: { clock.now() }, makeID: { generator.make() })
        return Seeded(store: store, service: service, fault: fault, project: board, other: other, ids: ids, url: destination)
    }

    private func corrupt(_ adapter: StoreAdapter, sequence: Int, project: UUID? = nil) throws {
        let models = try adapter.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>())
        let model = try #require(models.first { $0.sequence == sequence && (project == nil || $0.projectID == project) })
        model.snapshotData = Data("{\"schemaVersion\":1,".utf8)
        try adapter.save()
    }

    @Test("[W20-confirm-creates-restored-revision] 복원하면 그 revision과 이름·구성이 같은 새 revision이 현재가 된다", .tags(.A08))
    func restoreCreatesRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let (summary, snapshot) = try #require(try await s.service.restore(s.revisionID(2), in: s.project).committed)
            #expect(summary.sequence == 6)
            #expect(summary.cause == .restored(from: s.revisionID(2)))
            #expect(summary.projectName == "서비스 알파")
            #expect(snapshot == (try await s.snapshot(2)))
            #expect(try await s.currentRevisionID() == summary.id)
            #expect(try await s.current() == snapshot)
            #expect(try await s.count() == 6)
        }
    }

    @Test("[W20-history-and-checkpoints-preserved] 복원은 기존 revision과 체크포인트를 바꾸지 않는다", .tags(.A08))
    func historyAndCheckpointsPreserved() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory) { adapter, ids in
                try adapter.insert(CheckpointRecord(
                    id: fixedID(901), revisionID: ids[3]!, title: "1차 정리", progressNote: "", nextSteps: "",
                    createdAt: date(50), attachments: []
                ))
                try adapter.save()
            }
            let summariesBefore = Array(try await s.summaries().prefix(5))
            var snapshotsBefore: [ConfigurationSnapshot] = []
            for sequence in 1...5 { snapshotsBefore.append(try await s.snapshot(sequence)) }

            _ = try #require(try await s.service.restore(s.revisionID(2), in: s.project).committed)

            #expect(Array(try await s.summaries().prefix(5)) == summariesBefore)
            for sequence in 1...5 { #expect(try await s.snapshot(sequence) == snapshotsBefore[sequence - 1]) }
            #expect(try s.checkpointTitles(s.revisionID(3)) == ["1차 정리"])
            for sequence in [1, 2, 4, 5] { #expect(try s.checkpointTitles(s.revisionID(sequence)).isEmpty) }
            #expect(try s.checkpointTitles(try #require(try await s.currentRevisionID())).isEmpty)
        }
    }

    @Test("[W20-reuses-recorded-references] 복원된 항목은 기록된 참조를 그대로 쓰고 새 참조를 만들지 않는다")
    func reusesRecordedReferences() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let before = try #require(try await s.snapshot(2).node(named: "backend"))
            let referencesBefore = try await s.store.referenceCount()
            #expect(referencesBefore == 2)
            let restored = try #require(try await s.service.restore(s.revisionID(2), in: s.project).committed)
            let after = try #require(restored.snapshot.node(named: "backend"))
            #expect(after.referenceID == before.referenceID)
            #expect(after.id == before.id)
            #expect(try await s.store.referenceCount() == 2)
        }
    }

    @Test("[W20-name-only-restore] Board 이름만 다른 revision으로 복원하면 이름을 되돌리는 revision이 생긴다")
    func nameOnlyRestore() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let currentBefore = try await s.snapshot(5)
            let (summary, snapshot) = try #require(try await s.service.restore(s.revisionID(4), in: s.project).committed)
            #expect(summary.sequence == 6)
            #expect(summary.projectName == "서비스 알파")
            #expect(snapshot.nodes == currentBefore.nodes)
            #expect(currentBefore.projectName == "서비스 A")
        }
    }

    @Test("[W20-restore-chain] 복원으로 생긴 revision도 복원 대상이 되고 출처는 그 revision이다")
    func restoreChain() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let first = try #require(try await s.service.restore(s.revisionID(2), in: s.project).committed)
            #expect(first.summary.sequence == 6)
            let added = try #require(try await s.service.apply(.addGroup(name: "임시", parentID: nil, position: nil), to: s.project).committed)
            #expect(added.summary.sequence == 7)
            let second = try #require(try await s.service.restore(first.summary.id, in: s.project).committed)
            #expect(second.summary.sequence == 8)
            #expect(second.summary.cause == .restored(from: first.summary.id))
            #expect(second.snapshot == first.snapshot)
            #expect(second.snapshot.node(named: "임시") == nil)
            #expect(try await s.count() == 8)
        }
    }

    @Test("[W20-service-rejects-archived] 보관된 Board의 복원 요청은 거부되고 revision이 생기지 않는다")
    func archivedRejected() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            try await s.store.setArchived(s.project, at: date(100))
            let outcome = try await s.service.restore(s.revisionID(2), in: s.project)
            #expect(outcome == .rejected(.archived))
            #expect(try await s.count() == 5)
        }
    }

    @Test("[W20-service-rejects-foreign-revision] 없는 revision이나 다른 Board의 revision은 거부된다", arguments: [true, false])
    func foreignRevisionRejected(otherBoard: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let target: UUID
            if otherBoard {
                target = try #require(try await s.store.revisionSummaries(projectID: s.other).first).id
            } else {
                target = fixedID(404)
            }
            let outcome = try await s.service.restore(target, in: s.project)
            #expect(outcome == .rejected(.revisionNotFound))
            #expect(try await s.count() == 5)
            #expect(try await s.store.revisionSummaries(projectID: s.other).count == 1)
        }
    }

    @Test("[W20-service-target-unreadable] 대상 revision의 구성을 읽을 수 없으면 오류이고 빈 구성으로 대신하지 않는다")
    func unreadableTarget() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory) { adapter, _ in try corrupt(adapter, sequence: 2) }
            await #expect(throws: ConfigurationServiceError.targetConfigurationUnreadable) {
                try await s.service.restore(s.revisionID(2), in: s.project)
            }
            #expect(try await s.count() == 5)
            #expect(try await s.currentRevisionID() == s.revisionID(5))
        }
    }

    @Test("[W20-service-current-unreadable] 현재 구성을 읽을 수 없으면 오류이고 빈 구성으로 대신하지 않는다")
    func unreadableCurrent() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory) { adapter, _ in try corrupt(adapter, sequence: 5, project: nil) }
            await #expect(throws: ConfigurationServiceError.currentConfigurationUnreadable) {
                try await s.service.restore(s.revisionID(2), in: s.project)
            }
            #expect(try await s.count() == 5)
        }
    }

    @Test("[W20-restore_request_outcome-R5] 현재 revision으로의 복원 요청은 revision을 만들지 않는다")
    func restoringCurrentCreatesNothing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let outcome = try await s.service.restore(s.revisionID(5), in: s.project)
            #expect(outcome == .unchanged)
            #expect(try await s.count() == 5)
        }
    }

    @Test("저장이 실패하면 오류를 돌려주고 다시 시도하면 순번을 건너뛰지 않는다", .tags(.A13))
    func saveFailureThenRetry() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            s.fault.failNext()
            await #expect(throws: ConfigurationServiceError.saveFailed) {
                try await s.service.restore(s.revisionID(2), in: s.project)
            }
            #expect(try await s.count() == 5)
            #expect(try await s.currentRevisionID() == s.revisionID(5))
            let retried = try #require(try await s.service.restore(s.revisionID(2), in: s.project).committed)
            #expect(retried.summary.sequence == 6)
        }
    }

    @Test("없는 Board의 복원 요청은 거부된다")
    func missingBoardRejected() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let outcome = try await s.service.restore(s.revisionID(2), in: fixedID(404))
            #expect(outcome == .rejected(.projectNotFound))
        }
    }
}
