import Foundation
import Testing
@testable import Fianchetto

/// 과거 구성의 복사본(W21): 새 이름·새 Node ID·부모 재매핑. 참조 ID·당시 경로는 그대로다(0036).
@Suite("과거 구성 복사: ID 재매핑 (W21)")
struct ConfigurationDuplicatorTests {
    enum Shape: CaseIterable, CustomTestStringConvertible {
        case empty, singleBishop, nested, shuffled

        var testDescription: String {
            switch self {
            case .empty: "비어 있음"
            case .singleBishop: "최상위 Bishop 하나"
            case .nested: "3단 중첩"
            case .shuffled: "섞인 순서"
            }
        }

        var snapshot: ConfigurationSnapshot {
            switch self {
            case .empty:
                ConfigurationSnapshot(projectName: "원본", nodes: [])
            case .singleBishop:
                ConfigurationSnapshot(projectName: "원본", nodes: [
                    SnapshotFixtures.folder(fixedID(2), "backend", order: 0, reference: fixedID(102), path: "/dev/api"),
                ])
            case .nested:
                Self.nestedSnapshot
            case .shuffled:
                ConfigurationSnapshot(projectName: "원본", nodes: [
                    SnapshotFixtures.group(fixedID(14), "다섯", order: 4),
                    SnapshotFixtures.webLink(fixedID(10), "하나", order: 0, url: "https://example.com/1"),
                    SnapshotFixtures.file(fixedID(13), "넷.md", order: 3, reference: fixedID(113), path: "/docs/4.md"),
                    SnapshotFixtures.group(fixedID(11), "둘", order: 1),
                    SnapshotFixtures.folder(fixedID(12), "셋", order: 2, reference: fixedID(112), path: "/dev/3"),
                ])
            }
        }

        static let nestedSnapshot = ConfigurationSnapshot(projectName: "원본", nodes: [
            SnapshotFixtures.group(fixedID(1), "개발", order: 0),
            SnapshotFixtures.group(fixedID(5), "서버", parent: fixedID(1), order: 0),
            SnapshotFixtures.webLink(fixedID(6), "명세", parent: fixedID(5), order: 0, url: "https://example.com/spec"),
            ConfigurationNode(id: fixedID(7), kind: .file, displayName: "notes.md", parentID: fixedID(5), sortIndex: 1,
                              referenceID: fixedID(103), recordedPath: "/docs/notes.md", purpose: "document"),
            SnapshotFixtures.group(fixedID(8), "문서", order: 1),
        ])
    }

    /// ID를 뺀 구조: 종류·이름·부모 이름·순서·URL·아이콘·참조·당시 경로. (부모 이름, 순서)로 정렬한다.
    private func structure(_ snapshot: ConfigurationSnapshot) -> [[String]] {
        let names = Dictionary(snapshot.nodes.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        return snapshot.nodes.map { node in
            [node.kind.rawValue, node.displayName, node.parentID.flatMap { names[$0] } ?? "", String(node.sortIndex),
             node.url ?? "", node.purpose ?? "", node.referenceID?.uuidString ?? "", node.recordedPath ?? ""]
        }.sorted { ($0[2], $0[3]) < ($1[2], $1[3]) }
    }

    @Test("[W21-remap-preserves-structure] 복사본은 구조를 보존하고 새 ID만 쓰며 검사기를 통과한다", .tags(.A09), arguments: Shape.allCases)
    func preservesStructure(shape: Shape) {
        let source = shape.snapshot
        let ids = SequentialIDs()
        let copy = ConfigurationDuplicator.duplicate(source, projectName: "복사본", makeID: ids.next)
        #expect(copy.projectName == "복사본")
        #expect(copy.nodes.count == source.nodes.count)
        #expect(Set(copy.nodes.map(\.id)) == Set(ids.issued))
        #expect(Set(copy.nodes.map(\.id)).isDisjoint(with: source.nodes.map(\.id)))
        #expect(structure(copy) == structure(source))
        #expect(SnapshotValidator.violations(in: copy).isEmpty)
        for (old, new) in zip(source.nodes, copy.nodes) {
            let expectedParent = old.parentID.map { oldParent in copy.nodes[source.nodes.firstIndex { $0.id == oldParent }!].id }
            #expect(new.parentID == expectedParent)
            #expect(new.referenceID == old.referenceID)
            #expect(new.recordedPath == old.recordedPath)
        }
        let again = ConfigurationDuplicator.duplicate(source, projectName: "복사본", makeID: SequentialIDs().next)
        #expect(again == copy)
    }

    @Test("[W21-remap-leaves-source] 재매핑은 원본 구성을 바꾸지 않는다")
    func leavesSource() {
        let source = Shape.nestedSnapshot
        let before = source
        let idsBefore = source.nodes.map(\.id)
        _ = ConfigurationDuplicator.duplicate(source, projectName: "복사본", makeID: SequentialIDs().next)
        #expect(source == before)
        #expect(source.nodes.map(\.id) == idsBefore)
        #expect(source.nodes.map(\.parentID) == before.nodes.map(\.parentID))
        #expect(source.nodes.map(\.sortIndex) == before.nodes.map(\.sortIndex))
    }

    @Test("[W21-new-ids-remapped] 복사본의 ID는 원본 어느 Node와도 겹치지 않고 부모는 새 ID다", .tags(.A09))
    func remapsParents() throws {
        let source = Shape.nestedSnapshot
        let copy = ConfigurationDuplicator.duplicate(source, projectName: "복사본", makeID: SequentialIDs().next)
        let development = try #require(copy.node(named: "개발"))
        let server = try #require(copy.node(named: "서버"))
        #expect(server.parentID == development.id)
        #expect(copy.node(named: "명세")?.parentID == server.id)
        #expect(copy.node(named: "notes.md")?.parentID == server.id)
        #expect(Set(copy.nodes.map(\.id)).intersection(source.nodes.map(\.id)).isEmpty)
        #expect(copy.nodes.map(\.id).allSatisfy { !source.nodes.map(\.id).contains($0) })
    }
}
