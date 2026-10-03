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
    /// file·folder만: 용도 키(0021). 알려진 값은 BishopPurpose이며, 모르는 키도 그대로 보존한다.
    var purpose: String?

    init(
        id: UUID,
        kind: NodeKind,
        displayName: String,
        parentID: UUID? = nil,
        sortIndex: Int,
        referenceID: UUID? = nil,
        recordedPath: String? = nil,
        url: String? = nil,
        purpose: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.referenceID = referenceID
        self.recordedPath = recordedPath
        self.url = url
        self.purpose = purpose
    }
}

/// Bishop 용도의 알려진 저장 키(0021). 키는 바꾸지 않고, 화면 문구·기호는 DESIGN 18.2 표를 따른다.
enum BishopPurpose: String, CaseIterable, Sendable {
    case document
    case data
    case image
    case code
    case reference
    case presentation
    case todo
    case design
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
