import Foundation
import Testing
@testable import Fianchetto

/// 이력 행 병합(W22): revision 행은 순번 역순 그대로, 체크포인트 행은 기록 시각이 저장 시각 이하인 첫 revision 행 앞(없으면 맨 아래).
/// 같은 자리의 체크포인트끼리는 저장 시각 역순 → 연결 revision 순번 역순 → ID 문자열 순.
@Suite("이력 행 병합 (W22)")
struct HistoryTimelineTests {
    static func rev(_ n: Int, _ t: Double) -> RevisionSummary {
        RevisionSummary(
            id: fixedID(7000 + n), projectID: fixedID(500), sequence: n, recordedAt: date(t),
            cause: .edited(.renameNode), projectName: "서비스 A"
        )
    }

    static func cp(_ k: Int, _ n: Int, _ t: Double) -> CheckpointSummary {
        CheckpointSummary(id: fixedID(7100 + k), revisionID: fixedID(7000 + n), sequence: n, title: "c\(k)", createdAt: date(t))
    }

    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var revisions: [RevisionSummary]
        var checkpoints: [CheckpointSummary]
        var expected: [String]
        var testDescription: String { name }
    }

    // t1 < t1.5 < t2 < t3 < t4
    static let t1 = 10.0, t15 = 15.0, t2 = 20.0, t3 = 30.0, t4 = 40.0

    static let cases: [Case] = [
        Case(name: "비어 있음", revisions: [], checkpoints: [], expected: []),
        Case(name: "revision만", revisions: [rev(1, t1), rev(2, t2)], checkpoints: [], expected: ["#2", "#1"]),
        Case(name: "최신 revision 뒤 저장", revisions: [rev(1, t1), rev(2, t2)], checkpoints: [cp(1, 2, t3)], expected: ["c1", "#2", "#1"]),
        Case(name: "오래된 revision에 나중 저장", revisions: [rev(1, t1), rev(2, t2), rev(3, t3)], checkpoints: [cp(1, 1, t4)], expected: ["c1", "#3", "#2", "#1"]),
        Case(name: "기록 시각과 같은 저장 시각", revisions: [rev(1, t1), rev(2, t2)], checkpoints: [cp(1, 2, t2)], expected: ["c1", "#2", "#1"]),
        Case(name: "두 revision 사이 시각", revisions: [rev(1, t1), rev(2, t2)], checkpoints: [cp(1, 1, t15)], expected: ["#2", "c1", "#1"]),
        Case(name: "같은 revision 둘, 최신이 위", revisions: [rev(1, t1), rev(2, t2)], checkpoints: [cp(1, 2, t3), cp(2, 2, t4)], expected: ["c2", "c1", "#2", "#1"]),
        Case(name: "같은 시각, 순번 큰 쪽이 위", revisions: [rev(1, t1), rev(2, t2)], checkpoints: [cp(1, 1, t3), cp(2, 2, t3)], expected: ["c2", "c1", "#2", "#1"]),
        Case(name: "같은 시각·같은 revision, ID 순", revisions: [rev(1, t1), rev(2, t2)], checkpoints: [cp(1, 2, t3), cp(2, 2, t3)], expected: ["c1", "c2", "#2", "#1"]),
        Case(name: "불러오지 않은 revision, 나중 시각", revisions: [rev(2, t2)], checkpoints: [cp(1, 1, t3)], expected: ["c1", "#2"]),
        Case(name: "불러오지 않은 revision, 이른 시각", revisions: [rev(2, t2)], checkpoints: [cp(1, 1, t1)], expected: ["#2", "c1"]),
        Case(name: "체크포인트만", revisions: [], checkpoints: [cp(1, 1, t1)], expected: ["c1"]),
        Case(name: "시계 역행 revision", revisions: [rev(1, t2), rev(2, t1)], checkpoints: [], expected: ["#2", "#1"]),
        Case(name: "시계 역행 사이에 체크포인트", revisions: [rev(1, t2), rev(2, t1)], checkpoints: [cp(1, 1, t15), cp(2, 2, t3)], expected: ["c2", "c1", "#2", "#1"]),
        Case(name: "시계 역행, 같은 자리 둘", revisions: [rev(1, t2), rev(2, t1)], checkpoints: [cp(1, 1, t4), cp(2, 2, t1)], expected: ["c1", "c2", "#2", "#1"]),
    ]

    static func name(_ entry: HistoryTimeline.Entry) -> String {
        switch entry {
        case let .revision(summary): "#\(summary.sequence)"
        case let .checkpoint(summary): summary.title
        }
    }

    @Test("[W22-timeline-merge-pure] revision 행은 순번 역순 그대로, 체크포인트 행은 기록 시각이 저장 시각 이하인 첫 revision 행 앞", arguments: cases)
    func merge(_ c: Case) throws {
        try #require(fixedID(7101).uuidString < fixedID(7102).uuidString)
        let before = (c.revisions, c.checkpoints)
        let result = HistoryTimeline.merge(revisions: c.revisions, checkpoints: c.checkpoints)
        #expect(result.map(Self.name) == c.expected)
        #expect(c.revisions == before.0)
        #expect(c.checkpoints == before.1)
        #expect(HistoryTimeline.merge(revisions: c.revisions, checkpoints: c.checkpoints) == result)
        #expect(HistoryTimeline.merge(revisions: c.revisions.reversed(), checkpoints: c.checkpoints.reversed()) == result)
    }
}
