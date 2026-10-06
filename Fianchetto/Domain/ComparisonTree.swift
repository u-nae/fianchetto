import Foundation

/// 통합 트리의 한 행(W19, DESIGN.md 19.4). 이후 구성의 Node, 또는 이전 구성에만 있던 제거 Node다.
struct ComparisonRow: Equatable, Sendable, Identifiable {
    /// 행이 보이는 구성의 Node(제거 행은 이전 구성, 그 밖은 이후 구성).
    var node: ConfigurationNode
    /// 변화 종류(19.3 표 순서). 변화가 없으면 비어 있다.
    var kinds: [NodeChangeKind]
    var change: NodeChange?
    var children: [ComparisonRow]
    var id: UUID { node.id }
    var isRemoved: Bool { kinds.contains(.removed) }
}

/// 비교 요약(19.2): 변화 표시가 붙는 Node 수, 숨긴 순서 변경 수, Board 이름 변경 여부.
struct ComparisonSummary: Equatable, Sendable {
    var changedCount: Int
    var hiddenReorderCount: Int
    var boardRenamed: Bool
}

/// 결정 removed_row_placement(W19 명세 결정표)의 입력과 출력.
enum RemovedRowPlacement {
    enum ParentState: Sendable { case topLevel, kept, removed }
    enum Parent: Equatable, Sendable { case root, keptParentRow, removedParentRow }
    enum Position: Equatable, Sendable { case afterPrecedingSibling, first }

    static func decide(parent: ParentState, hasPrecedingSibling: Bool) -> (parent: Parent, position: Position) {
        let position: Position = hasPrecedingSibling ? .afterPrecedingSibling : .first
        switch parent {
        case .topLevel: return (.root, position)
        case .kept: return (.keptParentRow, position)
        case .removed: return (.removedParentRow, position)
        }
    }
}

/// 두 구성의 차이(W16)로 통합 트리를 만든다. 저장된 구성만 쓰는 순수 함수다(PRD §6-E).
enum ComparisonTree {
    /// 19.3 표 순서. 한 행의 여러 변화 문구를 이 순서로 잇는다.
    static let kindOrder: [NodeChangeKind] = [.added, .removed, .renamed, .moved, .reordered, .targetReplaced, .urlChanged, .purposeChanged]

    static func ordered(_ kinds: Set<NodeChangeKind>) -> [NodeChangeKind] {
        kindOrder.filter(kinds.contains)
    }

    /// 이후 구성 트리에 변화를 붙이고, 제거 Node를 이전 구성의 자리에 끼워 넣는다(결정 removed_row_placement).
    /// 이전 구성을 전위 순서로 처리해 같은 기준점 뒤에 붙는 제거 형제의 이전 순서를 지킨다.
    static func build(before: ConfigurationSnapshot, after: ConfigurationSnapshot, diff: ConfigurationDiff) -> [ComparisonRow] {
        let afterByID = Dictionary(after.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let beforeByID = Dictionary(before.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let changes = Dictionary(diff.changes.map { ($0.nodeID, $0) }, uniquingKeysWith: { first, _ in first })

        // 통합 트리의 부모(행 ID) → 자식 행 ID 목록. 이후 구성 구조에서 시작한다.
        var children: [UUID?: [UUID]] = [:]
        for (parentID, nodes) in grouped(after.nodes) {
            children[parentID] = nodes.map(\.id)
        }
        let beforeSiblings = grouped(before.nodes)

        for node in preorder(before.nodes) where afterByID[node.id] == nil {
            let parentState: RemovedRowPlacement.ParentState
            if let parentID = node.parentID {
                parentState = afterByID[parentID] != nil ? .kept : .removed
            } else {
                parentState = .topLevel
            }
            let container: UUID? = parentState == .topLevel ? nil : node.parentID
            let siblings = beforeSiblings[node.parentID] ?? []
            let index = siblings.firstIndex { $0.id == node.id } ?? 0
            let placed = children[container] ?? []
            let preceding = siblings[..<index].reversed().first { placed.contains($0.id) }
            let decision = RemovedRowPlacement.decide(parent: parentState, hasPrecedingSibling: preceding != nil)
            var list = placed
            switch decision.position {
            case .afterPrecedingSibling:
                let at = preceding.flatMap { sibling in list.firstIndex(of: sibling.id) }.map { $0 + 1 } ?? 0
                list.insert(node.id, at: at)
            case .first:
                list.insert(node.id, at: 0)
            }
            children[container] = list
        }

        func rows(under parentID: UUID?) -> [ComparisonRow] {
            (children[parentID] ?? []).compactMap { id in
                guard let node = afterByID[id] ?? beforeByID[id] else { return nil }
                let change = changes[id]
                return ComparisonRow(
                    node: node, kinds: ordered(change?.kinds ?? []), change: change,
                    children: node.kind == .group ? rows(under: id) : []
                )
            }
        }
        return rows(under: nil)
    }

    /// '순서 변경 표시'를 끄면 순서 변경을 빼고, '바뀐 항목만 보기'를 켜면 변화가 있는 행과 그 조상만 남긴다.
    static func filter(_ rows: [ComparisonRow], showsReorder: Bool, changedOnly: Bool) -> [ComparisonRow] {
        rows.compactMap { row in
            var copy = row
            if !showsReorder { copy.kinds.removeAll { $0 == .reordered } }
            copy.children = filter(row.children, showsReorder: showsReorder, changedOnly: changedOnly)
            if changedOnly, copy.kinds.isEmpty, copy.children.isEmpty { return nil }
            return copy
        }
    }

    static func summary(_ diff: ConfigurationDiff, showsReorder: Bool) -> ComparisonSummary {
        let reorderOnly = diff.changes.filter { $0.kinds == [.reordered] }.count
        return ComparisonSummary(
            changedCount: showsReorder ? diff.changes.count : diff.changes.count - reorderOnly,
            hiddenReorderCount: showsReorder ? 0 : reorderOnly,
            boardRenamed: diff.projectRename != nil
        )
    }

    private static func grouped(_ nodes: [ConfigurationNode]) -> [UUID?: [ConfigurationNode]] {
        var result: [UUID?: [ConfigurationNode]] = [:]
        for node in nodes { result[node.parentID, default: []].append(node) }
        for key in result.keys {
            result[key]!.sort { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
        }
        return result
    }

    private static func preorder(_ nodes: [ConfigurationNode]) -> [ConfigurationNode] {
        let children = grouped(nodes)
        var result: [ConfigurationNode] = []
        var visited: Set<UUID> = []
        func walk(_ parentID: UUID?) {
            for node in children[parentID] ?? [] where visited.insert(node.id).inserted {
                result.append(node)
                walk(node.id)
            }
        }
        walk(nil)
        return result
    }
}
