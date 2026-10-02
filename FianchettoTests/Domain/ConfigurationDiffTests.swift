import Foundation
import Testing
@testable import Fianchetto

@Suite("두 구성의 차이 계산 (W16)")
struct ConfigurationDiffTests {
    // MARK: 구성 A

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    static let dev = id(1), backend = id(2), memo = id(3), sub = id(4), deeper = id(5), docs = id(6), api = id(7)

    static func group(_ n: UUID, _ name: String, parent: UUID?, at index: Int) -> ConfigurationNode {
        ConfigurationNode(id: n, kind: .group, displayName: name, parentID: parent, sortIndex: index)
    }

    static func file(_ n: UUID, _ name: String, parent: UUID?, at index: Int, ref: Int, path: String) -> ConfigurationNode {
        ConfigurationNode(id: n, kind: .file, displayName: name, parentID: parent, sortIndex: index, referenceID: id(ref), recordedPath: path)
    }

    static func folder(_ n: UUID, _ name: String, parent: UUID?, at index: Int, ref: Int, path: String) -> ConfigurationNode {
        ConfigurationNode(id: n, kind: .folder, displayName: name, parentID: parent, sortIndex: index, referenceID: id(ref), recordedPath: path)
    }

    static func link(_ n: UUID, _ name: String, parent: UUID?, at index: Int, url: String) -> ConfigurationNode {
        ConfigurationNode(id: n, kind: .webLink, displayName: name, parentID: parent, sortIndex: index, url: url)
    }

    static let a = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
        group(dev, "개발", parent: nil, at: 0),
        folder(backend, "backend", parent: dev, at: 0, ref: 101, path: "/dev/legacy-api"),
        file(memo, "설계 메모", parent: dev, at: 1, ref: 102, path: "/docs/design.md"),
        group(sub, "하위", parent: dev, at: 2),
        group(deeper, "더 하위", parent: sub, at: 0),
        group(docs, "문서", parent: nil, at: 1),
        link(api, "API 명세", parent: nil, at: 2, url: "https://example.com/api"),
    ])

    /// 구성 A에서 Node 하나를 바꾼 구성.
    static func b(_ edits: (inout [ConfigurationNode]) -> Void, name: String = "서비스 A") -> ConfigurationSnapshot {
        var nodes = a.nodes
        edits(&nodes)
        return ConfigurationSnapshot(projectName: name, nodes: nodes)
    }

    static func edit(_ nodes: inout [ConfigurationNode], _ id: UUID, _ change: (inout ConfigurationNode) -> Void) {
        let index = nodes.firstIndex { $0.id == id }!
        change(&nodes[index])
    }

    /// 부모 아래 순서를 이름 목록대로 다시 매긴다.
    static func order(_ nodes: inout [ConfigurationNode], under parent: UUID?, _ ids: [UUID]) {
        for (index, id) in ids.enumerated() {
            edit(&nodes, id) { $0.parentID = parent; $0.sortIndex = index }
        }
    }

    private func diff(_ old: ConfigurationSnapshot, _ new: ConfigurationSnapshot) -> ConfigurationDiff {
        ConfigurationDiffer.diff(old, new)
    }

    private func change(_ result: ConfigurationDiff, _ id: UUID) -> NodeChange? {
        result.changes.first { $0.nodeID == id }
    }

    // MARK: 변화 없음

    @Test("[W16-empty-result] 같은 값·배열 순서만 다른 구성·빈 구성끼리는 빈 결과다", .tags(.A07))
    func emptyResult() {
        let copy = ConfigurationSnapshot(projectName: Self.a.projectName, nodes: Self.a.nodes)
        let shuffled = ConfigurationSnapshot(projectName: Self.a.projectName, nodes: Self.a.nodes.reversed())
        let empty = ConfigurationSnapshot(projectName: "빈 Board", nodes: [])
        for (old, new) in [(Self.a, copy), (Self.a, shuffled), (empty, empty)] {
            let result = diff(old, new)
            #expect(result.isEmpty)
            #expect(result.projectRename == nil)
            #expect(result.changes.isEmpty)
        }
    }

    // MARK: 분류별

    struct SingleCase: Sendable, CustomTestStringConvertible {
        var label: String
        var node: UUID
        var kind: NodeChangeKind
        var testDescription: String { label }
    }

    static let wiki = id(8)

    static func singleB(_ label: String) -> ConfigurationSnapshot {
        switch label {
        case "add": b { $0.append(link(wiki, "위키", parent: docs, at: 0, url: "https://example.com/wiki")) }
        case "remove": b { nodes in
            nodes.removeAll { $0.id == memo }
            edit(&nodes, sub) { $0.sortIndex = 1 }
        }
        case "rename": b { edit(&$0, backend) { $0.displayName = "api" } }
        case "move": b { nodes in
            edit(&nodes, memo) { $0.parentID = docs; $0.sortIndex = 0 }
            edit(&nodes, sub) { $0.sortIndex = 1 }
        }
        case "replace": b { edit(&$0, backend) { $0.referenceID = id(103); $0.recordedPath = "/dev/new-api" } }
        default: b { edit(&$0, api) { $0.url = "https://example.com/v2" } }
        }
    }

    static let singles: [SingleCase] = [
        SingleCase(label: "add", node: wiki, kind: .added),
        SingleCase(label: "remove", node: memo, kind: .removed),
        SingleCase(label: "rename", node: backend, kind: .renamed),
        SingleCase(label: "move", node: memo, kind: .moved),
        SingleCase(label: "replace", node: backend, kind: .targetReplaced),
        SingleCase(label: "url", node: api, kind: .urlChanged),
    ]

    @Test("[W16-single-kind] 각 변화는 그 분류 하나와 변경 전·후 값으로 보고된다", .tags(.A07), arguments: singles)
    func singleKind(single: SingleCase) throws {
        let result = diff(Self.a, Self.singleB(single.label))
        #expect(result.projectRename == nil)
        #expect(result.changes.map(\.nodeID) == [single.node])
        let item = try #require(result.changes.first)
        #expect(item.kinds == [single.kind])
        switch single.label {
        case "add":
            #expect(item.before == nil)
            #expect(item.after?.displayName == "위키")
            #expect(item.after?.location == ["문서"])
            #expect(item.nodeKind == .webLink)
        case "remove":
            #expect(item.after == nil)
            #expect(item.before?.displayName == "설계 메모")
            #expect(item.before?.location == ["개발"])
            #expect(item.before?.recordedPath == "/docs/design.md")
        case "rename":
            #expect(item.before?.displayName == "backend")
            #expect(item.after?.displayName == "api")
        case "move":
            #expect(item.before?.location == ["개발"])
            #expect(item.after?.location == ["문서"])
        case "replace":
            #expect(item.before?.recordedPath == "/dev/legacy-api")
            #expect(item.after?.recordedPath == "/dev/new-api")
        default:
            #expect(item.before?.url == "https://example.com/api")
            #expect(item.after?.url == "https://example.com/v2")
        }
    }

    @Test("[W16-project-rename] Board 이름 변경은 항목 변화와 따로 보고된다", .tags(.A07))
    func projectRename() {
        let result = diff(Self.a, Self.b({ _ in }, name: "서비스 A v2"))
        #expect(result.projectRename == ProjectRename(before: "서비스 A", after: "서비스 A v2"))
        #expect(result.changes.isEmpty)
        #expect(!result.isEmpty)
    }

    static let combinedB = b { nodes in
        edit(&nodes, backend) {
            $0.displayName = "api"
            $0.parentID = docs
            $0.sortIndex = 0
            $0.referenceID = id(103)
            $0.recordedPath = "/dev/new-api"
        }
        edit(&nodes, memo) { $0.sortIndex = 0 }
        edit(&nodes, sub) { $0.sortIndex = 1 }
    }

    @Test("[W16-combined-changes] 한 Node의 여러 변화는 한 항목에 함께 담긴다", .tags(.A07))
    func combinedChanges() throws {
        let result = diff(Self.a, Self.combinedB)
        #expect(result.changes.map(\.nodeID) == [Self.backend])
        let item = try #require(result.changes.first)
        #expect(item.kinds == [.renamed, .moved, .targetReplaced])
        #expect(item.before == NodeState(displayName: "backend", location: ["개발"], parentID: Self.dev, sortIndex: 0, recordedPath: "/dev/legacy-api", url: nil))
        #expect(item.after == NodeState(displayName: "api", location: ["문서"], parentID: Self.docs, sortIndex: 0, recordedPath: "/dev/new-api", url: nil))
    }

    @Test("[W16-location-path] 그룹 위치는 최상위부터의 그룹 이름 경로이고 최상위는 빈 경로다")
    func locationPath() {
        let deepMemo = Self.id(9)
        let new = Self.b { nodes in
            nodes.append(Self.file(deepMemo, "깊은 메모", parent: Self.deeper, at: 0, ref: 109, path: "/docs/deep.md"))
            nodes.append(Self.link(Self.wiki, "위키", parent: nil, at: 3, url: "https://example.com/wiki"))
        }
        let result = diff(Self.a, new)
        #expect(change(result, deepMemo)?.after?.location == ["개발", "하위", "더 하위"])
        #expect(change(result, Self.wiki)?.after?.location == [])
    }

    // MARK: 같은 이름의 다른 Node

    @Test("[W16-same-name-reinsert-is-different] 제거 후 같은 이름·경로로 다시 추가하면 제거 하나와 추가 하나다", .tags(.A07))
    func sameNameReinsert() {
        let newMemo = Self.id(10)
        let new = Self.b { nodes in
            nodes.removeAll { $0.id == Self.memo }
            nodes.append(Self.file(newMemo, "설계 메모", parent: Self.dev, at: 1, ref: 110, path: "/docs/design.md"))
        }
        let result = diff(Self.a, new)
        #expect(result.changes.count == 2)
        #expect(change(result, newMemo)?.kinds == [.added])
        #expect(change(result, Self.memo)?.kinds == [.removed])
    }

    @Test("[W16-same-name-siblings] 이름이 같은 형제 중 바뀐 Node만 보고한다", .tags(.A07))
    func sameNameSiblings() {
        let first = Self.id(11), second = Self.id(12)
        var nodes = Self.a.nodes
        nodes.append(Self.file(first, "메모", parent: Self.dev, at: 3, ref: 105, path: "/docs/memo-a.md"))
        nodes.append(Self.file(second, "메모", parent: Self.dev, at: 4, ref: 106, path: "/docs/memo-b.md"))
        let old = ConfigurationSnapshot(projectName: "서비스 A", nodes: nodes)
        Self.edit(&nodes, second) { $0.displayName = "메모 2" }
        let result = diff(old, ConfigurationSnapshot(projectName: "서비스 A", nodes: nodes))
        #expect(result.changes.map(\.nodeID) == [second])
        #expect(result.changes.first?.kinds == [.renamed])
    }

    // MARK: 이동과 자손

    @Test("[W16-group-move-no-descendants] 그룹을 옮기면 그 그룹만 이동으로 보고하고 자손·형제는 그대로다", .tags(.A07))
    func groupMoveNoDescendants() {
        // "문서"에 기존 자식을 둬 새 형제의 순서 변경이 없음을 실제로 확인한다.
        let paper = Self.id(13)
        var nodes = Self.a.nodes
        nodes.append(Self.file(paper, "논문", parent: Self.docs, at: 0, ref: 113, path: "/docs/paper.pdf"))
        let old = ConfigurationSnapshot(projectName: "서비스 A", nodes: nodes)
        Self.edit(&nodes, Self.sub) { $0.parentID = Self.docs; $0.sortIndex = 0 }
        Self.edit(&nodes, paper) { $0.sortIndex = 1 }
        let result = diff(old, ConfigurationSnapshot(projectName: "서비스 A", nodes: nodes))
        #expect(result.changes.map(\.nodeID) == [Self.sub])
        #expect(result.changes.first?.kinds == [.moved])
    }

    @Test("[W16-group-removal] 그룹과 자손을 제거하면 제거된 Node마다 보고한다", .tags(.A07))
    func groupRemoval() {
        let removed: Set<UUID> = [Self.dev, Self.backend, Self.memo, Self.sub, Self.deeper]
        let new = Self.b { nodes in
            nodes.removeAll { removed.contains($0.id) }
            Self.edit(&nodes, Self.docs) { $0.sortIndex = 0 }
            Self.edit(&nodes, Self.api) { $0.sortIndex = 1 }
        }
        let result = diff(Self.a, new)
        #expect(Set(result.changes.map(\.nodeID)) == removed)
        #expect(result.changes.allSatisfy { $0.kinds == [.removed] })
        #expect(result.changes.map(\.nodeID) == [Self.dev, Self.backend, Self.memo, Self.sub, Self.deeper])
    }

    // MARK: 순서 변경

    enum Shift: String, CaseIterable, Sendable { case frontInsert, frontRemove, moveOut }

    @Test("[W16-index-shift-not-reorder] 인덱스만 밀린 형제는 순서 변경이 아니다", .tags(.A07), arguments: Shift.allCases)
    func indexShiftNotReorder(shift: Shift) {
        let newGroup = Self.id(14)
        let new: ConfigurationSnapshot
        let expected: [UUID: Set<NodeChangeKind>]
        switch shift {
        case .frontInsert:
            new = Self.b { nodes in
                nodes.append(Self.group(newGroup, "새 그룹", parent: nil, at: 0))
                Self.order(&nodes, under: nil, [newGroup, Self.dev, Self.docs, Self.api])
            }
            expected = [newGroup: [.added]]
        case .frontRemove:
            let removed: Set<UUID> = [Self.dev, Self.backend, Self.memo, Self.sub, Self.deeper]
            new = Self.b { nodes in
                nodes.removeAll { removed.contains($0.id) }
                Self.order(&nodes, under: nil, [Self.docs, Self.api])
            }
            expected = Dictionary(uniqueKeysWithValues: removed.map { ($0, [NodeChangeKind.removed]) })
        case .moveOut:
            new = Self.b { nodes in
                Self.edit(&nodes, Self.backend) { $0.parentID = Self.docs; $0.sortIndex = 0 }
                Self.order(&nodes, under: Self.dev, [Self.memo, Self.sub])
            }
            expected = [Self.backend: [.moved]]
        }
        let result = diff(Self.a, new)
        #expect(Dictionary(uniqueKeysWithValues: result.changes.map { ($0.nodeID, $0.kinds) }) == expected)
    }

    struct ReorderCase: Sendable, CustomTestStringConvertible {
        var order: [Int]
        var reordered: [Int]
        var testDescription: String { "\(order) → \(reordered)" }
    }

    /// 2: backend, 3: 설계 메모, 4: 하위.
    static let reorders: [ReorderCase] = [
        ReorderCase(order: [3, 2, 4], reordered: [3]),
        ReorderCase(order: [3, 4, 2], reordered: [2]),
        ReorderCase(order: [4, 2, 3], reordered: [4]),
        ReorderCase(order: [4, 3, 2], reordered: [4, 3]),
    ]

    @Test("[W16-reorder-minimal] 실제로 순서가 바뀐 Node만 순서 변경으로 보고하고 전·후 정렬 순서를 준다", .tags(.A07), arguments: reorders)
    func reorderMinimal(reorder: ReorderCase) {
        let new = Self.b { Self.order(&$0, under: Self.dev, reorder.order.map(Self.id)) }
        let result = diff(Self.a, new)
        #expect(result.changes.map(\.nodeID) == reorder.reordered.map(Self.id))
        for item in result.changes {
            #expect(item.kinds == [.reordered])
            let oldIndex = Self.a.nodes.first { $0.id == item.nodeID }!.sortIndex
            let newIndex = new.nodes.first { $0.id == item.nodeID }!.sortIndex
            #expect(item.before?.sortIndex == oldIndex)
            #expect(item.after?.sortIndex == newIndex)
        }
    }

    @Test("[W16-reorder-tie-break] 이웃한 두 Node를 맞바꾸면 구성 A에서 뒤에 있던 Node가 순서 변경이다")
    func reorderTieBreak() {
        let new = Self.b { Self.order(&$0, under: Self.dev, [Self.backend, Self.sub, Self.memo]) }
        #expect(diff(Self.a, new).changes.map(\.nodeID) == [Self.sub])
    }

    @Test("[W16-insert-and-reorder] 앞쪽 추가와 실제 순서 변경이 함께 있으면 추가와 실제로 옮긴 Node만 보고한다", .tags(.A07))
    func insertAndReorder() {
        let newMemo = Self.id(15)
        let new = Self.b { nodes in
            nodes.append(Self.file(newMemo, "새 메모", parent: Self.dev, at: 0, ref: 115, path: "/docs/new.md"))
            Self.order(&nodes, under: Self.dev, [newMemo, Self.memo, Self.backend, Self.sub])
        }
        let result = diff(Self.a, new)
        #expect(Dictionary(uniqueKeysWithValues: result.changes.map { ($0.nodeID, $0.kinds) }) == [newMemo: [.added], Self.memo: [.reordered]])
    }

    @Test("[W16-move-excludes-reorder] 다른 그룹으로 옮긴 Node는 그룹 이동만 보고하고 새 형제를 바꾸지 않는다", .tags(.A07))
    func moveExcludesReorder() {
        let new = Self.b { Self.order(&$0, under: Self.dev, [Self.api, Self.backend, Self.memo, Self.sub]) }
        let result = diff(Self.a, new)
        #expect(result.changes.map(\.nodeID) == [Self.api])
        #expect(result.changes.first?.kinds == [.moved])
    }

    // MARK: 결과 순서와 순수성

    @Test("[W16-deterministic-order] 항목은 B 트리 순서의 변화 뒤에 A 트리 순서의 제거가 온다")
    func deterministicOrder() {
        let new = Self.b { nodes in
            nodes.append(Self.link(Self.wiki, "위키", parent: Self.docs, at: 0, url: "https://example.com/wiki"))
            Self.edit(&nodes, Self.backend) { $0.displayName = "api" }
            nodes.removeAll { $0.id == Self.api }
        }
        #expect(diff(Self.a, new).changes.map(\.nodeID) == [Self.backend, Self.wiki, Self.api])

        // 제거된 Node는 UUID 순이 아니라 구성 A의 트리 순서로 온다.
        let first = Self.id(20)
        var nodes = Self.a.nodes
        nodes.append(Self.group(first, "맨 앞", parent: nil, at: 0))
        Self.order(&nodes, under: nil, [first, Self.dev, Self.docs, Self.api])
        let old = ConfigurationSnapshot(projectName: "서비스 A", nodes: nodes)
        nodes.removeAll { $0.id == first || $0.id == Self.api }
        Self.order(&nodes, under: nil, [Self.dev, Self.docs])
        #expect(diff(old, ConfigurationSnapshot(projectName: "서비스 A", nodes: nodes)).changes.map(\.nodeID) == [first, Self.api])
    }

    @Test("[W16-pure] 고정 입력으로 비교해도 입력이 바뀌지 않고 다시 비교하면 같은 결과다")
    func pure() {
        let old = Self.a, new = Self.combinedB
        let first = diff(old, new)
        #expect(old == Self.a)
        #expect(old.nodes == Self.a.nodes)
        #expect(new.nodes == Self.combinedB.nodes)
        #expect(diff(old, new) == first)
    }

    enum Invalid: String, CaseIterable, Sendable { case orphan, cycle }

    @Test("[W16-invalid-input-terminates] 고아·순환이 있는 입력에도 비교가 끝나고 각 Node는 많아야 한 번 나온다", arguments: Invalid.allCases)
    func invalidInputTerminates(invalid: Invalid) {
        let one = Self.id(16), two = Self.id(17)
        let new = Self.b { nodes in
            switch invalid {
            case .orphan:
                nodes.append(Self.group(one, "고아", parent: Self.id(999), at: 0))
            case .cycle:
                nodes.append(Self.group(one, "순환 1", parent: two, at: 0))
                nodes.append(Self.group(two, "순환 2", parent: one, at: 0))
            }
        }
        for result in [diff(Self.a, new), diff(new, Self.a)] {
            let ids = result.changes.map(\.nodeID)
            #expect(ids.count == Set(ids).count)
            #expect(ids.contains(one))
        }
    }
}
