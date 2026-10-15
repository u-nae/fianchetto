import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 과거 구성으로 새 Board 만들기 서비스(W21): 결정표 duplicate_request_outcome과 저장 단위·독립성·참조 공유(0036).
@Suite("과거 구성에서 새 Board 만들기 서비스 (W21)")
struct DuplicateServiceTests {
    // MARK: 결정표 (spec-brief §4 duplicate_request_outcome, 32칸)

    enum Outcome: String, Sendable {
        case rejectedBlankName, rejectedProjectNotFound, rejectedRevisionNotFound, errorSourceUnreadable, created
    }

    enum Revision: String, Sendable { case found, notFound, otherBoard, unreadable }

    struct Cell: Sendable, CustomTestStringConvertible {
        var rule: String
        var blankName: Bool
        var projectFound: Bool
        var revision: Revision
        var archived: Bool
        var expected: Outcome

        var testDescription: String {
            "\(rule) blankName=\(blankName) projectFound=\(projectFound) revision=\(revision.rawValue) archived=\(archived) -> \(expected.rawValue)"
        }
    }

    static let cells: [Cell] = {
        var cells: [Cell] = []
        for projectFound in [true, false] {
            for revision in [Revision.found, .notFound, .otherBoard, .unreadable] {
                for archived in [false, true] {
                    cells.append(Cell(rule: "R1", blankName: true, projectFound: projectFound, revision: revision, archived: archived, expected: .rejectedBlankName))
                }
            }
        }
        for revision in [Revision.found, .notFound, .otherBoard, .unreadable] {
            for archived in [false, true] {
                cells.append(Cell(rule: "R2", blankName: false, projectFound: false, revision: revision, archived: archived, expected: .rejectedProjectNotFound))
            }
        }
        for revision in [Revision.notFound, .otherBoard] {
            for archived in [false, true] {
                cells.append(Cell(rule: "R3", blankName: false, projectFound: true, revision: revision, archived: archived, expected: .rejectedRevisionNotFound))
            }
        }
        for archived in [false, true] {
            cells.append(Cell(rule: "R4", blankName: false, projectFound: true, revision: .unreadable, archived: archived, expected: .errorSourceUnreadable))
        }
        for archived in [false, true] {
            cells.append(Cell(rule: "R5", blankName: false, projectFound: true, revision: .found, archived: archived, expected: .created))
        }
        return cells
    }()

    static let sourceProjectID = fixedID(10)
    static let sourceSummary = RevisionSummary(
        id: fixedID(21), projectID: sourceProjectID, sequence: 8, recordedAt: date(20), cause: .created, projectName: "서비스 알파"
    )
    static let sourceSnapshot = ConfigurationSnapshot(projectName: "서비스 알파", nodes: [
        SnapshotFixtures.group(fixedID(31), "개발", order: 0),
        SnapshotFixtures.folder(fixedID(32), "backend", parent: fixedID(31), order: 0, reference: fixedID(102), path: "/dev/api"),
    ])

    static func source(_ cell: Cell) -> DuplicationSource {
        guard cell.projectFound else { return .projectNotFound }
        let target: RestoreTarget = switch cell.revision {
        case .found: .found(sourceSummary, sourceSnapshot)
        case .notFound: .notFound
        case .otherBoard: .otherProject
        case .unreadable: .unreadable
        }
        let project = ProjectRecord(
            id: sourceProjectID, createdAt: date(0), currentRevisionID: fixedID(22),
            archivedAt: cell.archived ? date(5) : nil, origin: nil
        )
        return .found(project, target)
    }

    /// 판정을 결과 종류로 바꾼다. created면 새 Project·첫 revision의 출처·원인·구성도 함께 단언한다.
    static func classify(_ decision: DuplicationDecision<ConfigurationService.Decision>) -> Outcome {
        switch decision {
        case let .create(project, first):
            #expect(project.origin == ProjectOrigin(kind: .duplicate, sourceProjectID: sourceProjectID, sourceRevisionID: sourceSummary.id))
            #expect(project.archivedAt == nil)
            #expect(project.currentRevisionID == first.id)
            #expect(project.createdAt == first.recordedAt)
            #expect(project.id != sourceProjectID)
            #expect(first.cause == .duplicated)
            #expect(first.references.isEmpty)
            #expect(first.snapshot.projectName == "알파 2차")
            #expect(first.snapshot.nodes.count == sourceSnapshot.nodes.count)
            #expect(Set(first.snapshot.nodes.map(\.id)).isDisjoint(with: sourceSnapshot.nodes.map(\.id)))
            return .created
        case .skip(.outcome(.rejected(.blankName))): return .rejectedBlankName
        case .skip(.outcome(.rejected(.projectNotFound))): return .rejectedProjectNotFound
        case .skip(.outcome(.rejected(.revisionNotFound))): return .rejectedRevisionNotFound
        case .skip(.unreadableTarget): return .errorSourceUnreadable
        case .skip(.unreadableCurrent), .skip(.outcome): return .created // 결정표에 없는 결과. 기댓값과 달라 실패한다.
        }
    }

    static func decide(_ cell: Cell) -> DuplicationDecision<ConfigurationService.Decision> {
        let ids = TestIDs(startingAt: 7001)
        return ConfigurationService.decideDuplicate(
            named: cell.blankName ? "   " : "  알파 2차  ", source: source(cell), now: { date(99) }, makeID: { ids.make() }
        )
    }

    private func check(_ cell: Cell) {
        #expect(Self.classify(Self.decide(cell)) == cell.expected)
    }

    @Test("[W21-duplicate_request_outcome-R1] 정리한 이름이 비면 다른 입력과 무관하게 거부한다", arguments: cells.filter { $0.rule == "R1" })
    func blankNameRejects(cell: Cell) { check(cell) }

    @Test("[W21-duplicate_request_outcome-R2] 원본 Board가 없으면 거부한다", arguments: cells.filter { $0.rule == "R2" })
    func missingProjectRejects(cell: Cell) { check(cell) }

    @Test("[W21-duplicate_request_outcome-R3] 원본 revision이 없거나 다른 Board면 거부한다", arguments: cells.filter { $0.rule == "R3" })
    func missingRevisionRejects(cell: Cell) { check(cell) }

    @Test("[W21-duplicate_request_outcome-R4] 원본 revision의 구성을 읽을 수 없으면 원본 읽기 오류다", arguments: cells.filter { $0.rule == "R4" })
    func unreadableSourceErrors(cell: Cell) { check(cell) }

    @Test("[W21-duplicate_request_outcome-R5] 원본 revision을 읽었으면 보관 여부와 무관하게 새 Board를 만든다", arguments: cells.filter { $0.rule == "R5" })
    func foundCreates(cell: Cell) { check(cell) }

    @Test("[W21-service-outcome-table] 판정은 결정표와 같고 created일 때만 Project와 revision을 만든다")
    func decisionTable() {
        #expect(Self.cells.count == 32)
        for cell in Self.cells {
            let decision = Self.decide(cell)
            #expect(Self.classify(decision) == cell.expected, "\(cell.testDescription)")
            if case .create = decision {
                #expect(cell.expected == .created, "\(cell.testDescription)")
            } else {
                #expect(cell.expected != .created, "\(cell.testDescription)")
            }
        }
        #expect(Self.cells.filter { $0.expected == .created }.count == 2)
    }

    // MARK: 서비스 시나리오

    /// 복사한 저장소를 새 ID 번호대로 여는 서비스. seed가 쓴 번호와 겹치지 않는다.
    struct Seeded {
        let store: ProjectStore
        let service: ConfigurationService
        let fault: FaultPoint
        let bookmarks: ScriptedBookmarkSystem
        let project: UUID
        let other: UUID
        let ids: [Int: UUID]
        let url: URL
        let directory: URL
        private let copies = Counter()

        var replacement: TargetReplacementService {
            TargetReplacementService(bookmarks: BookmarkAdapter(system: bookmarks), configuration: service)
        }

        /// 지금까지 저장된 파일을 복사해 연 어댑터로 revision의 체크포인트 제목을 읽는다.
        func checkpointTitles(_ revisionID: UUID) throws -> [String] {
            let copy = url.deletingLastPathComponent().appending(path: "reopened-\(copies.next())/Fianchetto.store")
            try copyStoreFiles(from: url, to: copy)
            return try withStore(at: copy) { try $0.checkpoints(revisionID: revisionID).map(\.title) }
        }

        func revisionID(_ sequence: Int) -> UUID { ids[sequence]! }
        func summaries(of board: UUID? = nil) async throws -> [RevisionSummary] { try await store.revisionSummaries(projectID: board ?? project) }
        func count(of board: UUID? = nil) async throws -> Int { try await summaries(of: board).count }
        func snapshot(_ sequence: Int) async throws -> ConfigurationSnapshot { try await store.snapshot(revisionID: revisionID(sequence)) }
        func current(of board: UUID? = nil) async throws -> ConfigurationSnapshot { try await store.currentSnapshot(projectID: board ?? project) }
        func projectCount() async throws -> Int { try await store.projects().count }
        /// 원본 Board의 모든 revision에 등장한 Node ID.
        func allSourceNodeIDs() async throws -> Set<UUID> {
            var result: Set<UUID> = []
            for sequence in ids.keys { result.formUnion(try await snapshot(sequence).nodes.map(\.id)) }
            return result
        }

        /// 원본 순번 8("서비스 알파", 항목 전부)로 새 Board를 만든다.
        func dup(from sequence: Int = 8, named name: String = "서비스 C") async throws -> (summary: RevisionSummary, snapshot: ConfigurationSnapshot) {
            try #require(try await service.duplicateProject(from: revisionID(sequence), of: project, named: name).committed)
        }
    }

    /// 1 Board 만들기("서비스 알파"), 2 Bishop backend(legacy, 참조 R1), 3 대상 교체(v2, 참조 R2), 4 Wing "문서", 5 Wing "개발",
    /// 6 "개발" 안 웹 링크 "명세", 7 "개발" 안 Bishop notes.md(참조 R3), 8 notes.md 아이콘 document, 9 이름 "서비스 A". 다른 Board "서비스 B".
    /// `mutate`는 복사한 저장소 파일을 열어 손상이나 체크포인트를 더한다.
    private func seeded(
        _ directory: URL, mutate: (StoreAdapter, [Int: UUID]) throws -> Void = { _, _ in }
    ) async throws -> Seeded {
        let seed = try ServiceHarness(directory: directory.appending(path: "seed"))
        let legacy = try TargetFiles.folder(directory, "targets/legacy/backend")
        let v2 = try TargetFiles.folder(directory, "targets/v2/backend")
        let notes = try TargetFiles.file(directory, "targets/docs/notes.md", contents: "notes marker")
        let board = try await makeBoard(seed, "서비스 알파")
        _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [legacy]))
        let backend = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "backend")).id
        let replacement = TargetReplacementService(bookmarks: BookmarkAdapter(system: seed.bookmarks), configuration: seed.service)
        let preview = try await replacement.preview(projectID: board, nodeID: backend, newURL: v2).get()
        _ = try await replacement.confirm(preview)
        _ = try await seed.service.apply(.addGroup(name: "문서", parentID: nil, position: nil), to: board)
        let development = try #require(try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board).committed)
            .snapshot.node(named: "개발")!.id
        _ = try await seed.service.apply(.addWebLink(name: "명세", url: "https://example.com/spec", parentID: development, position: nil), to: board)
        _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: development, position: nil, urls: [notes]))
        let notesID = try #require(try await seed.store.currentSnapshot(projectID: board).node(named: "notes.md")).id
        _ = try await seed.service.apply(.changePurpose(notesID, "document"), to: board)
        _ = try await seed.service.apply(.renameProject("서비스 A"), to: board)
        let other = try await makeBoard(seed, "서비스 B")
        let summaries = try await seed.store.revisionSummaries(projectID: board)
        #expect(summaries.map(\.sequence) == [1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(summaries.first { $0.sequence == 8 }?.projectName == "서비스 알파")
        let ids = Dictionary(uniqueKeysWithValues: summaries.map { ($0.sequence, $0.id) })

        let destination = directory.appending(path: "tested/Fianchetto.store")
        try copyStoreFiles(from: seed.url, to: destination)
        try withStore(at: destination) { try mutate($0, ids) }

        let fault = FaultPoint()
        let store = ProjectStore(container: try StoreOpener.open(at: destination), beforeSave: { try fault.check() })
        let clock = TestClock(startingAt: date(1000)), generator = TestIDs(startingAt: 30001)
        let service = ConfigurationService(store: store, now: { clock.now() }, makeID: { generator.make() })
        return Seeded(
            store: store, service: service, fault: fault, bookmarks: seed.bookmarks, project: board, other: other,
            ids: ids, url: destination, directory: directory
        )
    }

    private func corrupt(_ adapter: StoreAdapter, sequence: Int) throws {
        let models = try adapter.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>())
        let model = try #require(models.first { $0.sequence == sequence })
        model.snapshotData = Data("{\"schemaVersion\":1,".utf8)
        try adapter.save()
    }

    /// ID를 뺀 구조: 종류·이름·부모 이름·순서·URL·아이콘·참조·당시 경로.
    private func structure(_ snapshot: ConfigurationSnapshot) -> [[String]] {
        let names = Dictionary(snapshot.nodes.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        return snapshot.nodes.map { node in
            [node.kind.rawValue, node.displayName, node.parentID.flatMap { names[$0] } ?? "", String(node.sortIndex),
             node.url ?? "", node.purpose ?? "", node.referenceID?.uuidString ?? "", node.recordedPath ?? ""]
        }.sorted { ($0[2], $0[3]) < ($1[2], $1[3]) }
    }

    @Test("[W21-origin-recorded] 새 Board는 원본 Board와 revision을 출처로 기록하고 보관되어 있지 않다")
    func originRecorded() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let (summary, _) = try await s.dup()
            let project = try #require(try await s.store.project(summary.projectID))
            #expect(project.origin == ProjectOrigin(kind: .duplicate, sourceProjectID: s.project, sourceRevisionID: s.revisionID(8)))
            #expect(project.archivedAt == nil)
            #expect(project.currentRevisionID == summary.id)
            #expect(project.createdAt == summary.recordedAt)
            #expect(summary.sequence == 1)
            #expect(summary.cause == .duplicated)
            #expect(summary.projectName == "서비스 C")
            #expect(summary.recordedAt == date(1000))
            #expect(summary.recordedAt != (try await s.summaries().first { $0.sequence == 8 }?.recordedAt))
            #expect(try await s.count(of: summary.projectID) == 1)
        }
    }

    @Test("[W21-new-ids-remapped] 새 Board와 Node는 새 UUID를 쓰고 부모 관계는 새 ID로 재매핑된다", .tags(.A09))
    func newIDsRemapped() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let (summary, snapshot) = try await s.dup()
            #expect(summary.projectID != s.project)
            #expect(Set(snapshot.nodes.map(\.id)).isDisjoint(with: try await s.allSourceNodeIDs()))
            let development = try #require(snapshot.node(named: "개발"))
            #expect(snapshot.node(named: "명세")?.parentID == development.id)
            #expect(snapshot.node(named: "notes.md")?.parentID == development.id)
            #expect(structure(snapshot) == structure(try await s.snapshot(8)))
            #expect(try await s.current(of: summary.projectID) == snapshot)
        }
    }

    @Test("[W21-shares-reference-records] 새 Board의 항목은 원본 revision의 참조 레코드를 그대로 쓰고 새 참조를 만들지 않는다")
    func sharesReferenceRecords() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let source = try await s.snapshot(8)
            #expect(try await s.store.referenceCount() == 3)
            let (_, snapshot) = try await s.dup()
            let backend = try #require(snapshot.node(named: "backend"))
            #expect(backend.referenceID == source.node(named: "backend")?.referenceID)
            #expect(backend.recordedPath == source.node(named: "backend")?.recordedPath)
            #expect(snapshot.node(named: "notes.md")?.referenceID == source.node(named: "notes.md")?.referenceID)
            #expect(try await s.store.referenceCount() == 3)
        }
    }

    @Test("[W21-source-preserved] 원본의 이력·체크포인트·현재 구성은 그대로이고 새 Board에는 체크포인트가 없다", .tags(.A09))
    func sourcePreserved() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory) { adapter, ids in
                try adapter.insert(CheckpointRecord(
                    id: fixedID(901), revisionID: ids[3]!, title: "1차 정리", progressNote: "", nextSteps: "",
                    createdAt: date(50), attachments: []
                ))
                try adapter.save()
            }
            let summariesBefore = try await s.summaries()
            var snapshotsBefore: [ConfigurationSnapshot] = []
            for sequence in 1...9 { snapshotsBefore.append(try await s.snapshot(sequence)) }
            let currentBefore = try await s.store.project(s.project)?.currentRevisionID

            let (summary, _) = try await s.dup()

            #expect(try await s.summaries() == summariesBefore)
            for sequence in 1...9 { #expect(try await s.snapshot(sequence) == snapshotsBefore[sequence - 1]) }
            #expect(try await s.store.project(s.project)?.currentRevisionID == currentBefore)
            #expect(try s.checkpointTitles(s.revisionID(3)) == ["1차 정리"])
            #expect(try s.checkpointTitles(summary.id).isEmpty)
            #expect(try await s.projectCount() == 3)
        }
    }

    @Test("[W21-independent-editing] 만든 뒤 원본과 새 Board의 편집은 서로 영향을 주지 않는다", .tags(.A09))
    func independentEditing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let (summary, snapshot) = try await s.dup()
            let copy = summary.projectID
            _ = try #require(try await s.service.apply(.addGroup(name: "임시", parentID: nil, position: nil), to: s.project).committed)
            _ = try #require(try await s.service.apply(.renameProject("서비스 C2"), to: copy).committed)
            let document = try #require(snapshot.node(named: "문서")).id
            _ = try #require(try await s.service.apply(.remove(document), to: copy).committed)

            let source = try await s.current()
            #expect(source.projectName == "서비스 A")
            #expect(source.node(named: "문서") != nil)
            #expect(source.node(named: "임시") != nil)
            let copied = try await s.current(of: copy)
            #expect(copied.projectName == "서비스 C2")
            #expect(copied.node(named: "임시") == nil)
            #expect(copied.node(named: "문서") == nil)
            #expect(try await s.count() == 10)
            #expect(try await s.count(of: copy) == 3)
        }
    }

    @Test("[W21-replace-target-independent] 새 Board에서 연결 대상을 바꾸면 새 참조가 생기고 원본의 참조는 그대로다")
    func replaceTargetIndependent() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let (summary, snapshot) = try await s.dup()
            let copy = summary.projectID
            let sharedReference = try #require(snapshot.node(named: "backend")?.referenceID)
            let v3 = try TargetFiles.folder(directory, "targets/v3/backend")
            let backend = try #require(snapshot.node(named: "backend")).id
            let preview = try await s.replacement.preview(projectID: copy, nodeID: backend, newURL: v3).get()
            _ = try await s.replacement.confirm(preview)

            let replaced = try #require(try await s.current(of: copy).node(named: "backend"))
            #expect(replaced.referenceID != sharedReference)
            #expect(try await s.store.referenceCount() == 4)
            #expect(try await s.current().node(named: "backend")?.referenceID == sharedReference)
            #expect(try await s.snapshot(8).node(named: "backend")?.referenceID == sharedReference)
        }
    }

    @Test("[W21-duplicate-chain] 복제로 만든 Board를 다시 복제하면 출처는 그 Board와 revision이다")
    func duplicateChain() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let (b, bSnapshot) = try await s.dup()
            let (d, dSnapshot) = try #require(try await s.service.duplicateProject(from: b.id, of: b.projectID, named: "서비스 D").committed)
            let project = try #require(try await s.store.project(d.projectID))
            #expect(project.origin == ProjectOrigin(kind: .duplicate, sourceProjectID: b.projectID, sourceRevisionID: b.id))
            let taken = try await s.allSourceNodeIDs().union(bSnapshot.nodes.map(\.id))
            #expect(Set(dSnapshot.nodes.map(\.id)).isDisjoint(with: taken))
            #expect(structure(dSnapshot) == structure(bSnapshot))
            #expect(try await s.projectCount() == 4)
        }
    }

    @Test("[W21-name-trimmed] 이름의 앞뒤 공백은 정리되어 저장된다")
    func nameTrimmed() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let (summary, snapshot) = try await s.dup(named: "  알파 2차  ")
            #expect(summary.projectName == "알파 2차")
            #expect(snapshot.projectName == "알파 2차")
            #expect(try await s.store.projectListings().first { $0.id == summary.projectID }?.name == "알파 2차")
        }
    }

    @Test("[W21-service-allows-archived-source] 보관된 원본 Board의 요청은 거부되지 않고 새 Board는 보관되지 않는다")
    func archivedSourceAllowed() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            try await s.store.setArchived(s.project, at: date(100))
            let (summary, _) = try await s.dup()
            #expect(try await s.store.project(summary.projectID)?.archivedAt == nil)
            #expect(try await s.store.project(s.project)?.archivedAt == date(100))
            #expect(try await s.count() == 9)
        }
    }

    @Test("[W21-service-rejects-foreign-revision] 없는 revision이나 다른 Board의 revision은 거부된다", arguments: [true, false])
    func foreignRevisionRejected(otherBoard: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let source: UUID
            if otherBoard {
                source = try #require(try await s.store.revisionSummaries(projectID: s.other).first).id
            } else {
                source = fixedID(404)
            }
            let outcome = try await s.service.duplicateProject(from: source, of: s.project, named: "서비스 C")
            #expect(outcome == .rejected(.revisionNotFound))
            #expect(try await s.projectCount() == 2)
        }
    }

    @Test("[W21-service-source-unreadable] 원본 revision의 구성을 읽을 수 없으면 오류이고 빈 구성으로 만들지 않는다")
    func unreadableSource() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory) { adapter, _ in try corrupt(adapter, sequence: 8) }
            await #expect(throws: ConfigurationServiceError.targetConfigurationUnreadable) {
                try await s.service.duplicateProject(from: s.revisionID(8), of: s.project, named: "서비스 C")
            }
            #expect(try await s.projectCount() == 2)
        }
    }

    @Test("[W21-service-atomic-commit] 저장이 실패하면 새 Project와 revision이 모두 남지 않고 참조 레코드도 그대로다")
    func atomicCommit() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            s.fault.failNext()
            await #expect(throws: ConfigurationServiceError.saveFailed) {
                try await s.service.duplicateProject(from: s.revisionID(8), of: s.project, named: "서비스 C")
            }
            #expect(try await s.projectCount() == 2)
            #expect(try await s.count() == 9)
            #expect(try await s.store.referenceCount() == 3)
            let (summary, _) = try await s.dup()
            #expect(summary.sequence == 1)
            #expect(try await s.projectCount() == 3)
        }
    }

    @Test("[W21-duplicate_request_outcome-R1] 공백뿐인 이름은 저장소를 바꾸지 않고 거부된다")
    func blankNameRejected() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let outcome = try await s.service.duplicateProject(from: s.revisionID(8), of: s.project, named: "   ")
            #expect(outcome == .rejected(.blankName))
            #expect(try await s.projectCount() == 2)
        }
    }

    @Test("[W21-duplicate_request_outcome-R2] 없는 Board의 요청은 거부된다")
    func missingBoardRejected() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let outcome = try await s.service.duplicateProject(from: s.revisionID(8), of: fixedID(404), named: "서비스 C")
            #expect(outcome == .rejected(.projectNotFound))
            #expect(try await s.projectCount() == 2)
        }
    }
}
