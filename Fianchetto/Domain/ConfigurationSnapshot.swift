import Foundation

enum NodeKind: String, Codable, CaseIterable, Sendable {
    case group
    case file
    case folder
    case webLink
}

/// Revision에 기록되는 Node 한 개의 값. 현재의 수정 가능한 모델과 공유하지 않는다(PRD §5 불변식 6·7).
struct ConfigurationNode: Codable, Hashable, Sendable {
    var id: UUID
    var kind: NodeKind
    var displayName: String
    /// nil이면 프로젝트 최상위.
    var parentID: UUID?
    /// 부모마다 0부터 빈틈없이 매기는 형제 순서.
    var sortIndex: Int
    /// file·folder만: 연결 대상 참조와 기록 당시 경로(0003).
    var referenceID: UUID?
    var recordedPath: String?
    /// webLink만: HTTP/HTTPS URL(0002). 검증이 잘못된 값을 보고할 수 있도록 문자열로 보존한다.
    var url: String?

    init(
        id: UUID,
        kind: NodeKind,
        displayName: String,
        parentID: UUID? = nil,
        sortIndex: Int,
        referenceID: UUID? = nil,
        recordedPath: String? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.referenceID = referenceID
        self.recordedPath = recordedPath
        self.url = url
    }
}

/// 특정 시점의 프로젝트 이름과 전체 Node 구성. 동등성은 Node 목록의 저장 순서를 무시한다.
struct ConfigurationSnapshot: Codable, Hashable, Sendable {
    var projectName: String
    var nodes: [ConfigurationNode]

    init(projectName: String, nodes: [ConfigurationNode]) {
        self.projectName = projectName
        self.nodes = nodes
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.projectName == rhs.projectName && lhs.canonicalNodes == rhs.canonicalNodes
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(projectName)
        hasher.combine(canonicalNodes)
    }

    private var canonicalNodes: [ConfigurationNode] {
        nodes.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
