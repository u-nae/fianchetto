import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 이력 목록 묶음 읽기와 날짜 시점 조회를 실제 SwiftData 저장소로 검증한다(W17).
@Suite("이력 질의(W17)")
struct HistoryQueryTests {
    /// Project 하나와 주어진 (순번, 기록 시각) revision들. 현재 revision은 가장 큰 순번이다.
    private func seed(_ store: StoreAdapter, _ revisions: [(Int, Date)]) throws {
        let last = try #require(revisions.max { $0.0 < $1.0 })
        try store.insert(RecordFixtures.projectRecord(current: fixedID(7000 + last.0)))
        for (sequence, recordedAt) in revisions {
            try store.insertRevision(RevisionDraft(
                id: fixedID(7000 + sequence), projectID: RecordFixtures.project, sequence: sequence,
                recordedAt: recordedAt, cause: sequence == 1 ? .created : .edited(.renameNode), snapshot: RecordFixtures.snapshot()
            ))
        }
        try store.save()
    }

    @Test("[W17-page-first] 첫 묶음은 가장 큰 순번부터 순번 역순으로 limit개다")
    func firstPage() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                try seed(store, (1...120).map { ($0, date(Double($0) * 86_400)) })
                let page = try store.revisionSummaries(projectID: RecordFixtures.project, below: nil, limit: 50)
                #expect(page.map(\.sequence) == Array((71...120).reversed()))
            }
        }
    }

    @Test("[W17-page-more] 다음 묶음은 받은 순번보다 작은 것부터 이어지고 끝에서는 남은 만큼만 온다")
    func nextPages() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                try seed(store, (1...120).map { ($0, date(Double($0) * 86_400)) })
                #expect(try store.revisionSummaries(projectID: RecordFixtures.project, below: 71, limit: 50).map(\.sequence) == Array((21...70).reversed()))
                #expect(try store.revisionSummaries(projectID: RecordFixtures.project, below: 21, limit: 50).map(\.sequence) == Array((1...20).reversed()))
                #expect(try store.revisionSummaries(projectID: RecordFixtures.project, below: 1, limit: 50).isEmpty)
                #expect(try store.revisionSummaries(projectID: RecordFixtures.otherProject, below: nil, limit: 50).isEmpty)
            }
        }
    }

    @Test("[W17-lookup-selects-row] 순번 범위로 읽으면 그 범위만 순번 역순으로 온다")
    func range() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                try seed(store, (1...10).map { ($0, date(Double($0))) })
                #expect(try store.revisionSummaries(projectID: RecordFixtures.project, sequences: 3...6).map(\.sequence) == [6, 5, 4, 3])
                #expect(try store.revisionSummaries(projectID: RecordFixtures.project, sequences: 11...20).isEmpty)
            }
        }
    }

    @Test("[W17-lookup-latest] 저장소 시점 조회는 기록 시각 이하에서 가장 늦은 시각, 같으면 큰 순번을 고른다", .tags(.A05))
    func latestMatchesDomainRule() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                // 순번 3은 시계가 뒤로 간 기록, 순번 4·5는 같은 시각.
                let revisions = [(1, date(0)), (2, date(300)), (3, date(100)), (4, date(400)), (5, date(400))]
                try seed(store, revisions)
                let domain = revisions.map { summary($0.0, at: $0.1) }
                for picked in [-1.0, 0, 99, 100, 150, 299, 300, 399, 400, 1_000] {
                    let stored = try store.latestRevision(projectID: RecordFixtures.project, atOrBefore: date(picked))?.sequence
                    #expect(stored == RevisionLookup.latest(atOrBefore: date(picked), in: domain)?.sequence, "picked \(picked)")
                }
                #expect(try store.latestRevision(projectID: RecordFixtures.project, atOrBefore: date(150))?.sequence == 3)
                #expect(try store.latestRevision(projectID: RecordFixtures.project, atOrBefore: date(400))?.sequence == 5)
                #expect(try store.latestRevision(projectID: RecordFixtures.project, atOrBefore: date(-1)) == nil)
            }
        }
    }

    @Test("[W17-decode-selected-only] 목록 묶음은 스냅샷이 손상된 revision도 디코딩 없이 읽는다")
    func pagesDoNotDecodeSnapshots() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                try seed(store, (1...3).map { ($0, date(Double($0))) })
                let damaged = try #require(try store.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>()).first { $0.sequence == 2 })
                damaged.snapshotData = Data("{".utf8)
                try store.save()
                #expect(try store.revisionSummaries(projectID: RecordFixtures.project, below: nil, limit: 50).map(\.sequence) == [3, 2, 1])
                #expect(throws: StoreReadError.self) { try store.snapshot(revisionID: fixedID(7002)) }
            }
        }
    }
}
