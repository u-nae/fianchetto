import Foundation

/// 과거 구성의 복사본(W21, PRD §6-F): Board 이름을 바꾸고 모든 Node에 새 UUID를 주며 부모 관계를 새 ID로 재매핑한다.
/// 종류·표시 이름·형제 순서·URL·아이콘·참조 ID·당시 경로는 그대로다(0036: 참조 레코드는 원본과 공유).
/// ID는 `nodes` 배열 순서대로 `makeID()`를 한 번씩 불러 정한다. 디스크·시간을 읽지 않는다.
enum ConfigurationDuplicator {
    static func duplicate(_ snapshot: ConfigurationSnapshot, projectName: String, makeID: () -> UUID) -> ConfigurationSnapshot {
        var mapping: [UUID: UUID] = [:]
        for node in snapshot.nodes {
            mapping[node.id] = makeID()
        }
        let nodes = snapshot.nodes.map { node in
            var copy = node
            copy.id = mapping[node.id] ?? node.id
            // 원본에 없는 부모(깨진 참조)는 재매핑 대상이 없으므로 그대로 둔다. 검사기를 통과한 원본에서는 생기지 않는다.
            copy.parentID = node.parentID.map { mapping[$0] ?? $0 }
            return copy
        }
        return ConfigurationSnapshot(projectName: projectName, nodes: nodes)
    }
}
