import Foundation
@testable import Fianchetto

/// 테스트용 고정 UUID. 무작위 값을 쓰지 않는다.
func fixedID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
}

enum SnapshotFixtures {
    static let development = fixedID(1)
    static let backend = fixedID(2)
    static let designNote = fixedID(3)
    static let apiSpec = fixedID(4)
    static let backendReference = fixedID(102)
    static let designNoteReference = fixedID(103)

    static func group(_ id: UUID, _ name: String, parent: UUID? = nil, order: Int) -> ConfigurationNode {
        ConfigurationNode(id: id, kind: .group, displayName: name, parentID: parent, sortIndex: order)
    }

    static func folder(_ id: UUID, _ name: String, parent: UUID? = nil, order: Int, reference: UUID, path: String) -> ConfigurationNode {
        ConfigurationNode(id: id, kind: .folder, displayName: name, parentID: parent, sortIndex: order,
                          referenceID: reference, recordedPath: path)
    }

    static func file(_ id: UUID, _ name: String, parent: UUID? = nil, order: Int, reference: UUID, path: String) -> ConfigurationNode {
        ConfigurationNode(id: id, kind: .file, displayName: name, parentID: parent, sortIndex: order,
                          referenceID: reference, recordedPath: path)
    }

    static func webLink(_ id: UUID, _ name: String, parent: UUID? = nil, order: Int, url: String) -> ConfigurationNode {
        ConfigurationNode(id: id, kind: .webLink, displayName: name, parentID: parent, sortIndex: order, url: url)
    }

    /// 대표 시나리오(PRD §2)의 축약 구성: 개발/backend, 개발/설계 메모, API 명세.
    static func serviceA() -> ConfigurationSnapshot {
        ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            group(development, "개발", order: 0),
            folder(backend, "backend", parent: development, order: 0, reference: backendReference, path: "/dev/legacy-api"),
            file(designNote, "설계 메모", parent: development, order: 1, reference: designNoteReference, path: "/docs/design.md"),
            webLink(apiSpec, "API 명세", order: 1, url: "https://example.com/api"),
        ])
    }
}

extension ConfigurationSnapshot {
    /// 지정한 Node를 바꾼 복사본.
    func updating(_ id: UUID, _ change: (inout ConfigurationNode) -> Void) -> ConfigurationSnapshot {
        var copy = self
        for index in copy.nodes.indices where copy.nodes[index].id == id {
            change(&copy.nodes[index])
        }
        return copy
    }
}
