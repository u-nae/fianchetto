import Foundation

/// 복제·가져오기로 만든 프로젝트의 출처. 세 값이 모두 있어야 한다(0005).
struct ProjectOrigin: Hashable, Sendable {
    enum Kind: String, Sendable {
        case duplicate
        case `import`
    }

    var kind: Kind
    var sourceProjectID: UUID
    var sourceRevisionID: UUID
}

/// 프로젝트 목록 관리 정보. 이름과 구성은 현재 revision이 가진다(0007).
struct ProjectRecord: Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var currentRevisionID: UUID
    var archivedAt: Date?
    var origin: ProjectOrigin?
}

/// revision이 생긴 원인(0005). 복원 출처는 restored에만 있다.
enum RevisionCause: Hashable, Sendable {
    /// W03 편집 연산과 같은 이름.
    enum EditKind: String, CaseIterable, Sendable {
        case renameProject
        case addGroup
        case addLinkedItems
        case addWebLink
        case renameNode
        case changeURL
        case move
        case remove
        case replaceTarget
    }

    case created
    case edited(EditKind)
    case restored(from: UUID)
    case duplicated
    case imported
}

/// 새 revision 하나. 프로젝트 이름과 스냅샷 schema version은 스냅샷에서 만든다.
struct RevisionDraft: Sendable {
    var id: UUID
    var projectID: UUID
    var sequence: Int
    var recordedAt: Date
    var cause: RevisionCause
    var snapshot: ConfigurationSnapshot
}

/// 스냅샷을 디코딩하지 않고 읽는 revision 목록 정보.
struct RevisionSummary: Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var sequence: Int
    var recordedAt: Date
    var cause: RevisionCause
    var projectName: String
}

/// 실제 대상 접근 정보. 북마크·마지막 해석 경로는 운영 정보로 갱신되며 revision을 바꾸지 않는다(0003, 불변식 8).
struct ResourceReferenceRecord: Hashable, Sendable {
    var id: UUID
    var initialPath: String
    var kind: LinkedTarget.Kind
    var bookmarkData: Data
    var lastResolvedPath: String?
}

struct AttachmentRecord: Hashable, Sendable {
    var id: UUID
    /// 앱 저장소 안의 상대 경로.
    var relativePath: String
    var mediaType: String
    var byteCount: Int
}

/// 저장 후 불변인 체크포인트. 첨부는 순서대로다.
struct CheckpointRecord: Hashable, Sendable {
    var id: UUID
    var revisionID: UUID
    var title: String
    var progressNote: String
    var nextSteps: String
    var createdAt: Date
    var attachments: [AttachmentRecord]
}
