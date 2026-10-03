import Foundation

/// 비교 결과의 한 Node 상태. 그룹 위치는 그 Node가 속한 스냅샷에서 최상위부터 직접 부모까지의 그룹 이름 경로다(최상위는 빈 경로).
struct NodeState: Equatable, Sendable {
    var displayName: String
    var location: [String]
    var parentID: UUID?
    var sortIndex: Int
    /// Bishop의 기록 당시 경로.
    var recordedPath: String?
    /// 웹 링크 URL.
    var url: String?
    /// Bishop 용도 키(저장 값 그대로, 0021).
    var purpose: String? = nil
}

enum NodeChangeKind: Hashable, Sendable, CaseIterable {
    case added
    case removed
    case renamed
    /// 직접 부모가 바뀌었다.
    case moved
    /// 같은 부모 안에서 공통 형제에 대한 상대 순서가 바뀌었다.
    case reordered
    case targetReplaced
    case urlChanged
    case purposeChanged
}

/// 한 Node의 변화. 여러 분류를 함께 담는다. 추가는 before가, 제거는 after가 없다.
struct NodeChange: Equatable, Sendable {
    var nodeID: UUID
    var nodeKind: NodeKind
    var kinds: Set<NodeChangeKind>
    var before: NodeState?
    var after: NodeState?
}

struct ProjectRename: Equatable, Sendable {
    var before: String
    var after: String
}

struct ConfigurationDiff: Equatable, Sendable {
    var projectRename: ProjectRename?
    /// B 트리 순서의 변화, 이어서 A 트리 순서의 제거.
    var changes: [NodeChange]

    var isEmpty: Bool { projectRename == nil && changes.isEmpty }
}

/// 같은 Board의 두 구성(A=이전, B=이후)을 Node UUID로만 맞춰 비교한다(PRD §6-E). 순수 함수이며 저장된 값만 쓴다.
/// 순서 변경은 인덱스가 아니라 공통 형제의 상대 순서로 판단해, 앞쪽 추가·제거로 인덱스만 밀린 형제는 보고하지 않는다.
enum ConfigurationDiffer {
    static func diff(_ a: ConfigurationSnapshot, _ b: ConfigurationSnapshot) -> ConfigurationDiff {
        let old = Index(a), new = Index(b)
        let reordered = reorderedNodes(old: old, new: new)
        var changes: [NodeChange] = []
        for node in new.preorder {
            guard let before = old.byID[node.id] else {
                changes.append(NodeChange(nodeID: node.id, nodeKind: node.kind, kinds: [.added], before: nil, after: new.state(of: node)))
                continue
            }
            var kinds: Set<NodeChangeKind> = []
            if before.displayName != node.displayName { kinds.insert(.renamed) }
            if before.parentID != node.parentID { kinds.insert(.moved) }
            if reordered.contains(node.id) { kinds.insert(.reordered) }
            if before.referenceID != node.referenceID { kinds.insert(.targetReplaced) }
            if before.url != node.url { kinds.insert(.urlChanged) }
            if before.purpose != node.purpose { kinds.insert(.purposeChanged) }
            guard !kinds.isEmpty else { continue }
            changes.append(NodeChange(nodeID: node.id, nodeKind: node.kind, kinds: kinds, before: old.state(of: before), after: new.state(of: node)))
        }
        for node in old.preorder where new.byID[node.id] == nil {
            changes.append(NodeChange(nodeID: node.id, nodeKind: node.kind, kinds: [.removed], before: old.state(of: node), after: nil))
        }
        let rename = a.projectName == b.projectName ? nil : ProjectRename(before: a.projectName, after: b.projectName)
        return ConfigurationDiff(projectRename: rename, changes: changes)
    }

    /// 부모마다, 두 구성 모두에서 그 부모 아래 있는 형제를 B 순서로 놓고 A 순서의 최장 증가 부분열 밖에 있는 Node를 고른다.
    private static func reorderedNodes(old: Index, new: Index) -> Set<UUID> {
        var result: Set<UUID> = []
        for (parentID, siblings) in new.children {
            // 두 구성 모두에서 같은 부모 아래 있는 형제만. 최상위(nil 부모)에서도 A에 없는 Node가 섞이지 않게 존재를 먼저 확인한다.
            let common = siblings.filter { node in
                guard let before = old.byID[node.id] else { return false }
                return before.parentID == parentID
            }
            guard common.count > 1 else { continue }
            let oldRanks = common.map { old.rank[$0.id]! }
            let kept = longestIncreasingIndices(oldRanks)
            for (offset, node) in common.enumerated() where !kept.contains(offset) {
                result.insert(node.id)
            }
        }
        return result
    }

    /// 값이 서로 다른 수열에서 최장 증가 부분열의 위치. 길이가 같은 후보가 여럿이면 값이 사전순으로 가장 앞선 것(구성 A에서 앞선 Node)을 고른다.
    static func longestIncreasingIndices(_ values: [Int]) -> Set<Int> {
        let n = values.count
        guard n > 0 else { return [] }
        // length[i]: i에서 시작하는 최장 증가 부분열 길이.
        var length = Array(repeating: 1, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in (i + 1)..<n where values[j] > values[i] {
                length[i] = max(length[i], length[j] + 1)
            }
        }
        var remaining = length.max()!
        var chosen: Set<Int> = []
        var lastIndex = -1, lastValue = Int.min
        while remaining > 0 {
            var pick: Int?
            for j in (lastIndex + 1)..<n where values[j] > lastValue && length[j] == remaining {
                if pick.map({ values[j] < values[$0] }) ?? true { pick = j }
            }
            guard let next = pick else { break }
            chosen.insert(next)
            lastIndex = next
            lastValue = values[next]
            remaining -= 1
        }
        return chosen
    }

    /// 스냅샷 하나의 조회 구조. 트리 검증을 통과하지 못한 입력(고아·순환)에도 각 Node를 한 번만 순회한다.
    private struct Index {
        var byID: [UUID: ConfigurationNode] = [:]
        var children: [UUID?: [ConfigurationNode]] = [:]
        /// 전위 순회 순서(형제는 정렬 순서, 같으면 UUID). 순회로 닿지 않은 Node는 UUID 순으로 뒤에 붙인다.
        var preorder: [ConfigurationNode] = []
        /// 같은 부모 안의 상대 순서를 비교할 수 있는 전체 순번.
        var rank: [UUID: Int] = [:]

        init(_ snapshot: ConfigurationSnapshot) {
            for node in snapshot.nodes where byID[node.id] == nil {
                byID[node.id] = node
            }
            for node in byID.values {
                children[node.parentID, default: []].append(node)
            }
            for key in children.keys {
                children[key]!.sort { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
            }
            var visited: Set<UUID> = []
            var stack = (children[nil] ?? []).reversed().map { $0 }
            func walk() {
                while let node = stack.popLast() {
                    guard visited.insert(node.id).inserted else { continue }
                    preorder.append(node)
                    stack.append(contentsOf: (children[node.id] ?? []).reversed())
                }
            }
            walk()
            for node in byID.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) where !visited.contains(node.id) {
                stack = [node]
                walk()
            }
            for (offset, node) in preorder.enumerated() { rank[node.id] = offset }
        }

        func state(of node: ConfigurationNode) -> NodeState {
            NodeState(
                displayName: node.displayName, location: location(of: node), parentID: node.parentID,
                sortIndex: node.sortIndex, recordedPath: node.recordedPath, url: node.url, purpose: node.purpose
            )
        }

        /// 최상위부터 직접 부모까지의 그룹 이름. 없는 부모나 순환을 만나면 그 지점에서 끊는다.
        private func location(of node: ConfigurationNode) -> [String] {
            var names: [String] = []
            var seen: Set<UUID> = [node.id]
            var parentID = node.parentID
            while let id = parentID, let parent = byID[id], seen.insert(id).inserted {
                names.append(parent.displayName)
                parentID = parent.parentID
            }
            return names.reversed()
        }
    }
}
