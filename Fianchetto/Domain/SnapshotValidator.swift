import Foundation

enum SnapshotViolationKind: String, Sendable {
    // 결정표 node_shape_validity 출력
    case parentNotGroup = "parent_not_group"
    case missingReference = "missing_reference"
    case incompleteReference = "incomplete_reference"
    case unexpectedReference = "unexpected_reference"
    case missingURL = "missing_url"
    case invalidURL = "invalid_url"
    case unexpectedURL = "unexpected_url"
    case purposeNotAllowed = "purpose_not_allowed"
    // 트리·이름 규칙
    case cycle
    case missingParent = "missing_parent"
    case duplicateNode = "duplicate_node"
    case siblingOrder = "sibling_order"
    case blankName = "blank_name"
    case untrimmedName = "untrimmed_name"
}

struct SnapshotViolation: Hashable, Sendable {
    enum Subject: Hashable, Sendable {
        case project
        case node(UUID)
        /// 형제 집합의 부모. nil이면 프로젝트 최상위.
        case siblings(parentID: UUID?)
    }

    var subject: Subject
    var kind: SnapshotViolationKind
}

/// 구성 스냅샷의 트리 규칙 검증. 서로 다른 규칙의 위반은 모두 보고하고, 위반이 없으면 빈 집합이다.
enum SnapshotValidator {
    static func violations(in snapshot: ConfigurationSnapshot) -> Set<SnapshotViolation> {
        var result = Set<SnapshotViolation>()
        if let kind = nameViolation(snapshot.projectName) {
            result.insert(SnapshotViolation(subject: .project, kind: kind))
        }

        var nodesByID: [UUID: ConfigurationNode] = [:]
        for node in snapshot.nodes {
            if nodesByID[node.id] == nil {
                nodesByID[node.id] = node
            } else {
                result.insert(SnapshotViolation(subject: .node(node.id), kind: .duplicateNode))
            }
        }

        for node in snapshot.nodes {
            func report(_ kind: SnapshotViolationKind) {
                result.insert(SnapshotViolation(subject: .node(node.id), kind: kind))
            }
            if let kind = nameViolation(node.displayName) { report(kind) }

            let parent: NodeShapeRule.ParentKind
            if let parentID = node.parentID {
                if let parentNode = nodesByID[parentID] {
                    parent = NodeShapeRule.ParentKind(parentNode.kind)
                } else {
                    report(.missingParent)
                    parent = .root // 부모 자격은 판정할 수 없으므로 Node 자체 필드만 본다.
                }
            } else {
                parent = .root
            }
            let shape = NodeShapeRule.evaluate(
                parent: parent,
                kind: node.kind,
                reference: NodeShapeRule.referenceFields(referenceID: node.referenceID, recordedPath: node.recordedPath),
                url: NodeShapeRule.urlShape(node.url),
                hasPurpose: node.purpose != nil
            )
            if let shape { report(shape) }

            if isOnCycle(node.id, parents: nodesByID) { report(.cycle) }
        }

        for (parentID, siblings) in Dictionary(grouping: snapshot.nodes, by: \.parentID) {
            if siblings.map(\.sortIndex).sorted() != Array(0..<siblings.count) {
                result.insert(SnapshotViolation(subject: .siblings(parentID: parentID), kind: .siblingOrder))
            }
        }
        return result
    }

    /// 저장된 이름은 고치지 않고, `DisplayName.normalize`를 통과한 형태인지만 판정한다.
    private static func nameViolation(_ name: String) -> SnapshotViolationKind? {
        do {
            return try DisplayName.normalize(name) == name ? nil : .untrimmedName
        } catch {
            return .blankName
        }
    }

    /// 부모를 따라 올라가 자기 자신으로 돌아오면 순환의 구성원이다. 순환에 매달린 자손은 해당하지 않는다.
    private static func isOnCycle(_ id: UUID, parents nodesByID: [UUID: ConfigurationNode]) -> Bool {
        var current = nodesByID[id]?.parentID
        var steps = 0
        while let next = current, steps <= nodesByID.count {
            if next == id { return true }
            current = nodesByID[next]?.parentID
            steps += 1
        }
        return false
    }
}
