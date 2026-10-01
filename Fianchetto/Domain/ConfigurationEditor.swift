import Foundation

/// 연결할 실제 파일·폴더 하나. 표시 이름 기본값(대상 이름)은 호출자가 정한다.
struct LinkedTarget: Hashable, Sendable {
    enum Kind: Sendable {
        case file
        case folder

        var nodeKind: NodeKind {
            switch self {
            case .file: .file
            case .folder: .folder
            }
        }
    }

    var displayName: String
    var kind: Kind
    /// 절대 경로. 기록 당시 경로로 저장된다.
    var path: String
}

/// 확정된 사용자 작업 하나. 위치가 nil이면 목적 부모의 끝이다.
enum ConfigurationEdit: Sendable {
    case renameProject(String)
    case addGroup(name: String, parentID: UUID?, position: Int?)
    case addLinkedItems([LinkedTarget], parentID: UUID?, position: Int?)
    case addWebLink(name: String, url: String, parentID: UUID?, position: Int?)
    case renameNode(UUID, String)
    case changeURL(UUID, String)
    /// 같은 부모 안의 순서 변경도 이동이다. 위치는 이동할 Node를 뺀 목적 형제 목록 기준이다.
    case move(UUID, toParent: UUID?, position: Int?)
    /// Node와 모든 자손을 제거한다.
    case remove(UUID)
    case replaceTarget(UUID, kind: LinkedTarget.Kind, path: String, identity: TargetIdentity)
}

/// 거부 사유. 여럿이면 선언 순서상 앞선 사유 하나를 돌려준다(존재 → 종류 → 배치 → 이름 → 값 → 위치).
enum EditRejection: String, Error, Sendable {
    case nodeNotFound = "node_not_found"
    case notWebLink = "not_web_link"
    case notLinkedItem = "not_linked_item"
    case parentNotGroup = "parent_not_group"
    case cycle
    case blankName = "blank_name"
    case targetKindMismatch = "target_kind_mismatch"
    case invalidPath = "invalid_path"
    case invalidURL = "invalid_url"
    case invalidPosition = "invalid_position"
}

enum EditOutcome: Equatable, Sendable {
    case changed(ConfigurationSnapshot)
    /// 결과가 입력과 같다. revision을 만들지 않는다.
    case unchanged
    /// 유효하지 않은 입력이다. revision을 만들지 않는다.
    case rejected(EditRejection)
}

/// 구성 편집 연산. 순수 함수이며 입력 스냅샷을 바꾸지 않는다. 새 UUID는 `makeID`가 요청 순서대로 내준다.
enum ConfigurationEditor {
    static func apply(
        _ edit: ConfigurationEdit,
        to snapshot: ConfigurationSnapshot,
        makeID: () -> UUID
    ) -> EditOutcome {
        var draft = Draft(snapshot)
        do {
            try draft.perform(edit, makeID: makeID)
        } catch {
            return .rejected(error)
        }
        let result = draft.snapshot
        return result == snapshot ? .unchanged : .changed(result)
    }
}

private struct Draft {
    var snapshot: ConfigurationSnapshot

    init(_ snapshot: ConfigurationSnapshot) {
        self.snapshot = snapshot
    }

    mutating func perform(_ edit: ConfigurationEdit, makeID: () -> UUID) throws(EditRejection) {
        switch edit {
        case let .renameProject(name):
            snapshot.projectName = try normalizedName(name)

        case let .addGroup(name, parentID, position):
            try requireGroupParent(parentID)
            let name = try normalizedName(name)
            try requireInsertPosition(position, under: parentID)
            insert([ConfigurationNode(id: makeID(), kind: .group, displayName: name, sortIndex: 0)], under: parentID, at: position)

        case let .addLinkedItems(targets, parentID, position):
            try requireGroupParent(parentID)
            var checked: [(name: String, target: LinkedTarget)] = []
            for target in targets {
                let name = try normalizedName(target.displayName)
                try requireAbsolutePath(target.path)
                checked.append((name, target))
            }
            try requireInsertPosition(position, under: parentID)
            let nodes = checked.map { name, target in
                let id = makeID()
                return ConfigurationNode(
                    id: id, kind: target.kind.nodeKind, displayName: name, sortIndex: 0,
                    referenceID: makeID(), recordedPath: target.path
                )
            }
            insert(nodes, under: parentID, at: position)

        case let .addWebLink(name, url, parentID, position):
            try requireGroupParent(parentID)
            let name = try normalizedName(name)
            let url = try normalizedURL(url)
            try requireInsertPosition(position, under: parentID)
            insert([ConfigurationNode(id: makeID(), kind: .webLink, displayName: name, sortIndex: 0, url: url)], under: parentID, at: position)

        case let .renameNode(id, name):
            let index = try requireNode(id)
            snapshot.nodes[index].displayName = try normalizedName(name)

        case let .changeURL(id, url):
            let index = try requireNode(id)
            guard snapshot.nodes[index].kind == .webLink else { throw .notWebLink }
            snapshot.nodes[index].url = try normalizedURL(url)

        case let .move(id, parentID, position):
            let index = try requireNode(id)
            try requireGroupParent(parentID)
            if let parentID, parentID == id || isDescendant(parentID, of: id) { throw .cycle }
            let destination = siblings(of: parentID).filter { $0 != id }
            if let position, !(0...destination.count).contains(position) { throw .invalidPosition }
            let origin = snapshot.nodes[index].parentID
            var ordered = destination
            ordered.insert(id, at: position ?? destination.count)
            snapshot.nodes[index].parentID = parentID
            renumber(ordered)
            if origin != parentID {
                renumber(siblings(of: origin))
            }

        case let .remove(id):
            let index = try requireNode(id)
            let parentID = snapshot.nodes[index].parentID
            let removed = Set([id] + descendants(of: id))
            snapshot.nodes.removeAll { removed.contains($0.id) }
            renumber(siblings(of: parentID))

        case let .replaceTarget(id, kind, path, identity):
            let index = try requireNode(id)
            let node = snapshot.nodes[index]
            guard node.kind == .file || node.kind == .folder else { throw .notLinkedItem }
            guard node.kind == kind.nodeKind else { throw .targetKindMismatch }
            try requireAbsolutePath(path)
            guard identity != .sameTarget else { return }
            snapshot.nodes[index].referenceID = makeID()
            snapshot.nodes[index].recordedPath = path
        }
    }

    // MARK: 검사

    private func requireNode(_ id: UUID) throws(EditRejection) -> Int {
        guard let index = snapshot.nodes.firstIndex(where: { $0.id == id }) else { throw .nodeNotFound }
        return index
    }

    /// 목적 부모가 최상위(nil)이거나 존재하는 그룹이어야 한다.
    private func requireGroupParent(_ parentID: UUID?) throws(EditRejection) {
        guard let parentID else { return }
        let parent = snapshot.nodes[try requireNode(parentID)]
        guard parent.kind == .group else { throw .parentNotGroup }
    }

    private func requireInsertPosition(_ position: Int?, under parentID: UUID?) throws(EditRejection) {
        guard let position else { return }
        guard (0...siblings(of: parentID).count).contains(position) else { throw .invalidPosition }
    }

    private func requireAbsolutePath(_ path: String) throws(EditRejection) {
        guard path.hasPrefix("/") else { throw .invalidPath }
    }

    private func normalizedName(_ name: String) throws(EditRejection) -> String {
        do {
            return try DisplayName.normalize(name)
        } catch {
            throw .blankName
        }
    }

    private func normalizedURL(_ url: String) throws(EditRejection) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NodeShapeRule.urlShape(trimmed) == .httpOrHTTPS else { throw .invalidURL }
        return trimmed
    }

    // MARK: 트리

    /// 부모 아래 Node UUID를 정렬 순서대로.
    private func siblings(of parentID: UUID?) -> [UUID] {
        snapshot.nodes.filter { $0.parentID == parentID }.sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
    }

    private func descendants(of id: UUID) -> [UUID] {
        let children = snapshot.nodes.filter { $0.parentID == id }.map(\.id)
        return children + children.flatMap(descendants(of:))
    }

    private func isDescendant(_ candidate: UUID, of ancestor: UUID) -> Bool {
        descendants(of: ancestor).contains(candidate)
    }

    private mutating func insert(_ nodes: [ConfigurationNode], under parentID: UUID?, at position: Int?) {
        var ordered = siblings(of: parentID)
        ordered.insert(contentsOf: nodes.map(\.id), at: position ?? ordered.count)
        snapshot.nodes += nodes.map { node in
            var node = node
            node.parentID = parentID
            return node
        }
        renumber(ordered)
    }

    /// 주어진 순서대로 정렬 순서를 0부터 다시 매긴다.
    private mutating func renumber(_ ordered: [UUID]) {
        let order = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
        for index in snapshot.nodes.indices {
            if let sortIndex = order[snapshot.nodes[index].id] {
                snapshot.nodes[index].sortIndex = sortIndex
            }
        }
    }
}
