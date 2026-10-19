import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 체크포인트 저장 서비스(W22): 결정표 checkpoint_request_outcome과 저장 단위·불변·Board 단위 조회.
@Suite("체크포인트 저장 서비스 (W22)")
struct CheckpointServiceTests {
    // MARK: 결정표 (spec-brief §4 checkpoint_request_outcome, 48칸)

    enum Outcome: String, Sendable {
        case rejectedBlankTitle, rejectedProjectNotFound, rejectedArchived, rejectedRevisionNotFound, saved
    }

    enum Revision: String, Sendable { case found, notFound, otherBoard }

    struct Cell: Sendable, CustomTestStringConvertible {
        var rule: String
        var blankTitle: Bool
        var projectFound: Bool
        var archived: Bool
        var revision: Revision
        var current: Bool
        var expected: Outcome

        var testDescription: String {
            "\(rule) blankTitle=\(blankTitle) projectFound=\(projectFound) archived=\(archived) revision=\(revision.rawValue) current=\(current) -> \(expected.rawValue)"
        }
    }

    static let cells: [Cell] = {
        var cells: [Cell] = []
        let revisions: [Revision] = [.found, .notFound, .otherBoard]
        for projectFound in [true, false] {
            for archived in [false, true] {
                for revision in revisions {
                    for current in [true, false] {
                        cells.append(Cell(rule: "R1", blankTitle: true, projectFound: projectFound, archived: archived, revision: revision, current: current, expected: .rejectedBlankTitle))
                    }
                }
            }
        }
        for archived in [false, true] {
            for revision in revisions {
                for current in [true, false] {
                    cells.append(Cell(rule: "R2", blankTitle: false, projectFound: false, archived: archived, revision: revision, current: current, expected: .rejectedProjectNotFound))
                }
            }
        }
        for revision in revisions {
            for current in [true, false] {
                cells.append(Cell(rule: "R3", blankTitle: false, projectFound: true, archived: true, revision: revision, current: current, expected: .rejectedArchived))
            }
        }
        for revision in [Revision.notFound, .otherBoard] {
            for current in [true, false] {
                cells.append(Cell(rule: "R4", blankTitle: false, projectFound: true, archived: false, revision: revision, current: current, expected: .rejectedRevisionNotFound))
            }
        }
        for current in [true, false] {
            cells.append(Cell(rule: "R5", blankTitle: false, projectFound: true, archived: false, revision: .found, current: current, expected: .saved))
        }
        return cells
    }()

    static let projectID = fixedID(10)
    static let summary = RevisionSummary(
        id: fixedID(21), projectID: projectID, sequence: 5, recordedAt: date(20), cause: .edited(.addGroup), projectName: "서비스 A"
    )

    static func source(_ cell: Cell) -> CheckpointSource {
        guard cell.projectFound else { return .projectNotFound }
        let revision: CheckpointRevision = switch cell.revision {
        case .found: .found(summary)
        case .notFound: .notFound
        case .otherBoard: .otherProject
        }
        let project = ProjectRecord(
            id: projectID, createdAt: date(0), currentRevisionID: cell.current ? summary.id : fixedID(22),
            archivedAt: cell.archived ? date(5) : nil, origin: nil
        )
        return .found(project, revision)
    }

    /// 판정을 결과 종류로 바꾼다. saved면 레코드 필드도 함께 단언한다.
    static func classify(_ decision: CheckpointDecision<CommitRejection>) -> Outcome {
        switch decision {
        case let .save(record):
            #expect(record.id == fixedID(7001))
            #expect(record.revisionID == fixedID(21))
            #expect(record.title == "인증 1차")
            #expect(record.progressNote == "로그인 완료\n")
            #expect(record.nextSteps == "토큰 갱신")
            #expect(record.createdAt == date(99))
            #expect(record.attachments.isEmpty)
            return .saved
        case .skip(.blankTitle): return .rejectedBlankTitle
        case .skip(.projectNotFound): return .rejectedProjectNotFound
        case .skip(.archived): return .rejectedArchived
        case .skip(.revisionNotFound): return .rejectedRevisionNotFound
        case .skip: return .saved // 결정표에 없는 결과. 기댓값과 달라 실패한다.
        }
    }

    static func decide(_ cell: Cell) -> CheckpointDecision<CommitRejection> {
        ConfigurationService.decideCheckpoint(
            title: cell.blankTitle ? " \n\t " : "  인증 1차 ", progressNote: "로그인 완료\n", nextSteps: "토큰 갱신",
            source: source(cell), now: { date(99) }, makeID: { fixedID(7001) }
        )
    }

    private func check(_ cell: Cell) {
        #expect(Self.classify(Self.decide(cell)) == cell.expected)
    }

    @Test("[W22-checkpoint_request_outcome-R1] 정리한 제목이 비면 다른 입력과 무관하게 거부한다", arguments: cells.filter { $0.rule == "R1" })
    func blankTitleRejects(cell: Cell) { check(cell) }

    @Test("[W22-checkpoint_request_outcome-R2] Board가 없으면 거부한다", arguments: cells.filter { $0.rule == "R2" })
    func missingProjectRejects(cell: Cell) { check(cell) }

    @Test("[W22-checkpoint_request_outcome-R3] 보관된 Board면 거부한다(0009)", arguments: cells.filter { $0.rule == "R3" })
    func archivedRejects(cell: Cell) { check(cell) }

    @Test("[W22-checkpoint_request_outcome-R4] revision이 없거나 다른 Board면 거부한다", arguments: cells.filter { $0.rule == "R4" })
    func foreignRevisionRejects(cell: Cell) { check(cell) }

    @Test("[W22-checkpoint_request_outcome-R5] 그 Board의 revision이면 현재 여부와 무관하게 저장한다", arguments: cells.filter { $0.rule == "R5" })
    func saves(cell: Cell) { check(cell) }

    @Test("[W22-service-outcome-table] 결정표의 모든 칸은 정확히 한 규칙이 이긴다")
    func tableCoversEveryCell() {
        #expect(Self.cells.count == 48)
        let keys = Self.cells.map { "\($0.blankTitle)-\($0.projectFound)-\($0.archived)-\($0.revision.rawValue)-\($0.current)" }
        #expect(Set(keys).count == 48)
    }

    // MARK: 서비스·저장소 시나리오

    struct Seeded {
        let harness: ServiceHarness
        let project: UUID
        let other: UUID
        let ids: [Int: UUID]
        var store: ProjectStore { harness.store }
        func revisionID(_ sequence: Int) -> UUID { ids[sequence]! }
        func summaries() async throws -> [RevisionSummary] { try await store.revisionSummaries(projectID: project) }
        func currentRevisionID() async throws -> UUID? { try await store.project(project)?.currentRevisionID }
        func checkpoints(of sequence: Int) async throws -> [CheckpointSummary] {
            try await store.checkpointSummaries(projectID: project).filter { $0.sequence == sequence }
        }
        func checkpointCount() async throws -> Int { try await store.checkpointSummaries(projectID: project).count }
    }

    /// 1 Board "서비스 A", 2 Bishop 폴더 backend, 3 Wing 개발, 4 웹 링크 명세(개발 아래), 5 Wing 문서, 6 명세 URL 변경. 현재 순번 6. 다른 Board "서비스 Z".
    private func seeded(_ directory: URL) async throws -> Seeded {
        let harness = try ServiceHarness(directory: directory.appending(path: "seed"))
        let backend = try TargetFiles.folder(directory, "targets/backend")
        _ = try TargetFiles.file(directory, "targets/backend/marker.txt", contents: "marker")
        let board = try await makeBoard(harness, "서비스 A")
        _ = try await harness.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [backend]))
        let development = try #require(try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board).committed)
            .snapshot.node(named: "개발")!.id
        let spec = try #require(try await harness.service.apply(
            .addWebLink(name: "명세", url: "https://example.com/spec", parentID: development, position: nil), to: board
        ).committed).snapshot.node(named: "명세")!.id
        _ = try await harness.service.apply(.addGroup(name: "문서", parentID: nil, position: nil), to: board)
        _ = try await harness.service.apply(.changeURL(spec, "https://example.com/spec-v2"), to: board)
        let other = try await makeBoard(harness, "서비스 Z")
        let summaries = try await harness.store.revisionSummaries(projectID: board)
        #expect(summaries.map(\.sequence) == [1, 2, 3, 4, 5, 6])
        return Seeded(harness: harness, project: board, other: other, ids: Dictionary(uniqueKeysWithValues: summaries.map { ($0.sequence, $0.id) }))
    }

    /// `at`이 있으면 그 시각을 내는 시계의 서비스로, 없으면 하네스 서비스로 저장한다.
    private func save(
        _ s: Seeded, _ title: String = "인증 1차", note: String = "로그인 완료", next: String = "토큰 갱신",
        on sequence: Int = 6, at: Double? = nil
    ) async throws -> CheckpointOutcome {
        let service: ConfigurationService
        if let at {
            let ids = TestIDs(startingAt: 9001 + Int(at))
            service = ConfigurationService(store: s.store, now: { date(at) }, makeID: { ids.make() })
        } else {
            service = s.harness.service
        }
        return try await service.saveCheckpoint(title: title, progressNote: note, nextSteps: next, on: s.revisionID(sequence), in: s.project)
    }

    private func saved(_ outcome: CheckpointOutcome) throws -> CheckpointRecord {
        guard case let .saved(record) = outcome else { throw TestFailure("saved가 아니다: \(outcome)") }
        return record
    }

    struct TestFailure: Error { let message: String; init(_ message: String) { self.message = message } }

    @Test("[W22-service-record-fields] 저장된 레코드는 고정 revision·정리한 제목·입력 그대로의 메모·주입 시계 시각·빈 첨부를 가지고 revision은 그대로다", .tags(.A10))
    func recordFields() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let record = try saved(try await save(s, "  인증 1차 ", note: "로그인 완료\n", at: 5000))
            #expect(record.revisionID == s.revisionID(6))
            #expect(record.title == "인증 1차")
            #expect(record.progressNote == "로그인 완료\n")
            #expect(record.nextSteps == "토큰 갱신")
            #expect(record.createdAt == date(5000))
            #expect(record.attachments.isEmpty)
            #expect(try await s.summaries().count == 6)
            #expect(try await s.currentRevisionID() == s.revisionID(6))
            #expect(try await s.store.checkpoint(record.id) == record)
            let second = try saved(try await save(s, "  인증 1차 ", note: "로그인 완료\n", at: 5001))
            #expect(second.id != record.id)
            #expect(try await s.checkpoints(of: 6).count == 2)
        }
    }

    @Test("[W22-title-trimmed-notes-verbatim] 제목은 앞뒤 공백을 정리하고 메모는 줄바꿈까지 그대로 저장한다")
    func titleTrimmed() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let record = try saved(try await save(s, "  인증 1차  ", note: "로그인 완료\n토큰 갱신 남음", next: "  갱신 구현 "))
            #expect(record.title == "인증 1차")
            #expect(record.progressNote == "로그인 완료\n토큰 갱신 남음")
            #expect(record.nextSteps == "  갱신 구현 ")
        }
    }

    @Test("[W22-optional-notes-empty] 진행 메모와 다음 할 일이 비어 있어도 저장된다")
    func emptyNotes() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let record = try saved(try await save(s, "빈 메모", note: "", next: ""))
            #expect(record.progressNote == "")
            #expect(record.nextSteps == "")
            #expect(try await s.checkpointCount() == 1)
        }
    }

    @Test("[W22-multiple-checkpoints-same-revision] 같은 revision에 여러 체크포인트를 붙일 수 있고 목록은 저장 시각 역순이다", .tags(.A10))
    func multiple() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let first = try saved(try await save(s, "1차", at: 100))
            let second = try saved(try await save(s, "2차", at: 200))
            let list = try await s.store.checkpointSummaries(projectID: s.project)
            #expect(list.map(\.title) == ["2차", "1차"])
            #expect(list.map(\.sequence) == [6, 6])
            #expect(first.id != second.id)
            #expect(try await s.summaries().count == 6)
        }
    }

    @Test("[W22-checkpoint-immutable-after-edit] 저장 뒤 구성이 바뀌어도 체크포인트는 원래 revision에 그대로다", .tags(.A10))
    func immutable() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let record = try saved(try await save(s, "1차"))
            _ = try await s.harness.service.apply(.addGroup(name: "임시", parentID: nil, position: nil), to: s.project)
            let summaries = try await s.summaries()
            #expect(summaries.count == 7)
            #expect(try await s.currentRevisionID() == summaries.last?.id)
            let list = try await s.store.checkpointSummaries(projectID: s.project)
            #expect(list.count == 1)
            #expect(list.first?.sequence == 6)
            #expect(try await s.store.checkpoint(record.id) == record)
            #expect(try await s.checkpoints(of: 7).isEmpty)
        }
    }

    @Test("[W22-service-atomic-commit] 저장이 실패하면 아무것도 남지 않고 복구 뒤 다시 저장할 수 있다")
    func atomic() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            s.harness.fault.failNext()
            await #expect(throws: ConfigurationServiceError.saveFailed) { try await save(s, "실패") }
            #expect(try await s.checkpointCount() == 0)
            #expect(try await s.summaries().count == 6)
            #expect(try await s.currentRevisionID() == s.revisionID(6))
            _ = try saved(try await save(s, "실패"))
            #expect(try await s.checkpointCount() == 1)
        }
    }

    @Test("[W22-service-rejects-foreign-revision] 없는 revision이나 다른 Board의 revision에는 붙이지 않는다", arguments: [true, false])
    func foreignRevision(otherBoard: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let revision = otherBoard ? try #require(try await s.store.revisionSummaries(projectID: s.other).first?.id) : fixedID(404)
            let outcome = try await s.harness.service.saveCheckpoint(title: "남의 것", progressNote: "", nextSteps: "", on: revision, in: s.project)
            #expect(outcome == .rejected(.revisionNotFound))
            #expect(try await s.checkpointCount() == 0)
            #expect(try await s.store.checkpointSummaries(projectID: s.other).isEmpty)
        }
    }

    @Test("[W22-service-rejects-archived] 보관된 Board에는 저장하지 않고 보관 해제 뒤에는 저장한다")
    func archived() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            try await s.store.setArchived(s.project, at: date(100))
            #expect(try await save(s, "보관 중") == .rejected(.archived))
            #expect(try await s.checkpointCount() == 0)
            try await s.store.setArchived(s.project, at: nil)
            _ = try saved(try await save(s, "보관 중"))
            #expect(try await s.checkpointCount() == 1)
        }
    }

    @Test("[W22-checkpoint_request_outcome-R2] 없는 Board의 요청은 거부된다")
    func missingBoard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let s = try await seeded(directory)
            let outcome = try await s.harness.service.saveCheckpoint(title: "없는 Board", progressNote: "", nextSteps: "", on: s.revisionID(6), in: fixedID(404))
            #expect(outcome == .rejected(.projectNotFound))
            #expect(try await s.checkpointCount() == 0)
        }
    }

    @Test("[W22-history-paging-keeps-rows] Board의 체크포인트 목록은 모든 revision의 것을 순번과 함께 한 번에 읽고 다른 Board의 것은 뺀다")
    func summariesPerBoard() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let staging = directory.appending(path: "staging/Fianchetto.store")
            let c2 = fixedID(522), c3 = fixedID(523), otherRevision = fixedID(8001)
            try withStore(at: staging) { store throws in
                try seedBasicRecords(store)
                try store.insert(RecordFixtures.projectRecord(RecordFixtures.otherProject, current: otherRevision))
                try store.insertRevision(RecordFixtures.revision(otherRevision, project: RecordFixtures.otherProject, sequence: 1, at: 10))
                try store.insert(CheckpointRecord(id: c2, revisionID: RecordFixtures.r1, title: "첫 revision 메모", progressNote: "", nextSteps: "", createdAt: date(90), attachments: []))
                try store.insert(CheckpointRecord(id: c3, revisionID: otherRevision, title: "다른 Board", progressNote: "", nextSteps: "", createdAt: date(70), attachments: []))
                try store.save()
            }
            let url = directory.appending(path: "tested/Fianchetto.store")
            try copyStoreFiles(from: staging, to: url)
            let store = ProjectStore(container: try StoreOpener.open(at: url))
            let list = try await store.checkpointSummaries(projectID: RecordFixtures.project)
            #expect(list.map(\.id) == [c2, RecordFixtures.c1])
            #expect(list.map(\.sequence) == [1, 2])
            #expect(list.map(\.createdAt) == [date(90), date(60)])
            #expect(list.map(\.title) == ["첫 revision 메모", "인증 리팩토링 1차 완료"])
            #expect(try await store.checkpointSummaries(projectID: RecordFixtures.otherProject).map(\.id) == [c3])
            #expect(try await store.checkpointSummaries(projectID: fixedID(404)).isEmpty)
            #expect(try await store.currentRevisionSummary(projectID: RecordFixtures.project)?.id == RecordFixtures.r2)
            #expect(try await store.currentRevisionSummary(projectID: fixedID(404)) == nil)
        }
    }
}
