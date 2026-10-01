import Foundation
import SwiftData

/// 영구 저장 스키마 V1. 현재 구성은 Project가 가리키는 revision의 스냅샷이며 Node 모델은 없다(0007).
/// ID 열에 unique 제약을 쓰지 않는다. unique는 같은 값 삽입을 덮어쓰므로 불변 revision을 바꿀 수 있다.
/// 중복은 StoreAdapter가 삽입 전에 거부한다.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [ProjectModel.self, RevisionModel.self, ResourceReferenceModel.self, CheckpointModel.self, AttachmentModel.self]
    }

    @Model
    final class ProjectModel {
        var id: UUID
        var createdAt: Date
        var currentRevisionID: UUID
        var archivedAt: Date?
        var originKind: String?
        var originProjectID: UUID?
        var originRevisionID: UUID?

        init(
            id: UUID, createdAt: Date, currentRevisionID: UUID, archivedAt: Date?,
            originKind: String?, originProjectID: UUID?, originRevisionID: UUID?
        ) {
            self.id = id
            self.createdAt = createdAt
            self.currentRevisionID = currentRevisionID
            self.archivedAt = archivedAt
            self.originKind = originKind
            self.originProjectID = originProjectID
            self.originRevisionID = originRevisionID
        }
    }

    @Model
    final class RevisionModel {
        var id: UUID
        var projectID: UUID
        var sequence: Int
        var recordedAt: Date
        var cause: String
        var restoredFromRevisionID: UUID?
        var projectName: String
        var snapshotSchemaVersion: Int
        var snapshotData: Data

        init(
            id: UUID, projectID: UUID, sequence: Int, recordedAt: Date, cause: String,
            restoredFromRevisionID: UUID?, projectName: String, snapshotSchemaVersion: Int, snapshotData: Data
        ) {
            self.id = id
            self.projectID = projectID
            self.sequence = sequence
            self.recordedAt = recordedAt
            self.cause = cause
            self.restoredFromRevisionID = restoredFromRevisionID
            self.projectName = projectName
            self.snapshotSchemaVersion = snapshotSchemaVersion
            self.snapshotData = snapshotData
        }
    }

    @Model
    final class ResourceReferenceModel {
        var id: UUID
        var initialPath: String
        var kind: String
        var bookmarkData: Data
        var lastResolvedPath: String?

        init(id: UUID, initialPath: String, kind: String, bookmarkData: Data, lastResolvedPath: String?) {
            self.id = id
            self.initialPath = initialPath
            self.kind = kind
            self.bookmarkData = bookmarkData
            self.lastResolvedPath = lastResolvedPath
        }
    }

    @Model
    final class CheckpointModel {
        var id: UUID
        var revisionID: UUID
        var title: String
        var progressNote: String
        var nextSteps: String
        var createdAt: Date
        @Relationship(deleteRule: .cascade, inverse: \AttachmentModel.checkpoint)
        var attachments: [AttachmentModel] = []

        init(id: UUID, revisionID: UUID, title: String, progressNote: String, nextSteps: String, createdAt: Date) {
            self.id = id
            self.revisionID = revisionID
            self.title = title
            self.progressNote = progressNote
            self.nextSteps = nextSteps
            self.createdAt = createdAt
        }
    }

    @Model
    final class AttachmentModel {
        var id: UUID
        var relativePath: String
        var mediaType: String
        var byteCount: Int
        var order: Int
        var checkpoint: CheckpointModel?

        init(id: UUID, relativePath: String, mediaType: String, byteCount: Int, order: Int) {
            self.id = id
            self.relativePath = relativePath
            self.mediaType = mediaType
            self.byteCount = byteCount
            self.order = order
        }
    }
}

/// 앱의 스키마 이전 계획. 스키마를 바꿀 때 새 VersionedSchema와 단계를 여기에 더한다.
enum FianchettoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
