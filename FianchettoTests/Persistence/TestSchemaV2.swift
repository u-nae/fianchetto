import Foundation
import SwiftData
@testable import Fianchetto

/// 테스트 전용 다음 스키마: V1의 다섯 모델에 Revision 선택 필드 `note` 하나를 더한다.
enum TestSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SchemaV1.ProjectModel.self, RevisionModel.self, SchemaV1.ResourceReferenceModel.self,
         SchemaV1.CheckpointModel.self, SchemaV1.AttachmentModel.self]
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
        var note: String?

        init(id: UUID, projectID: UUID, sequence: Int, recordedAt: Date, cause: String, projectName: String, snapshotData: Data) {
            self.id = id
            self.projectID = projectID
            self.sequence = sequence
            self.recordedAt = recordedAt
            self.cause = cause
            self.projectName = projectName
            self.snapshotSchemaVersion = 1
            self.snapshotData = snapshotData
        }
    }
}

enum TestMigrationPlanV2: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, TestSchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: SchemaV1.self, toVersion: TestSchemaV2.self)] }
}

/// V2만 아는(앱보다 새로운) 이전 계획. 이 계획으로 만든 저장소는 앱의 V1 계획이 모른다.
enum TestNewerOnlyPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TestSchemaV2.self] }
    static var stages: [MigrationStage] { [] }
}
