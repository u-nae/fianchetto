import Foundation
import SwiftData

enum StoreWriteError: Error, Equatable, Sendable {
    case duplicateProject(UUID)
    case duplicateRevision(UUID)
    case duplicateSequence(projectID: UUID, sequence: Int)
    case duplicateReference(UUID)
    case duplicateCheckpoint(UUID)
    case missingProject(UUID)
    case missingRevision(UUID)
    case missingReference(UUID)
    case snapshotEncodingFailed
    case storeUnavailable
}

enum StoreReadError: Error, Equatable, Sendable {
    /// 저장 레코드가 Domain 형태 규칙(0005 등)을 어긴다.
    case damagedRecord(UUID)
    case snapshot(SnapshotDecodingError)
    case notFound(UUID)
    case storeUnavailable
}

/// 저장소 모델과 Domain 레코드 사이의 경계. @Model 타입은 이 밖으로 나가지 않는다.
/// 이미 있는 레코드를 덮어쓰지 않는다(불변식 4). Revision·Checkpoint는 추가만 하고 수정·삭제하지 않는다.
/// 갱신할 수 있는 것은 운영 정보뿐이다: 참조의 북마크·마지막 해석 경로, Project의 현재 revision·보관 시각.
/// ModelContext를 감싸므로 Task·actor 경계를 넘기지 않는다.
struct StoreAdapter {
    let context: ModelContext

    // MARK: 추가

    func insert(_ project: ProjectRecord) throws(StoreWriteError) {
        guard try projectModel(project.id) == nil else { throw .duplicateProject(project.id) }
        context.insert(SchemaV1.ProjectModel(
            id: project.id, createdAt: project.createdAt, currentRevisionID: project.currentRevisionID,
            archivedAt: project.archivedAt, originKind: project.origin?.kind.rawValue,
            originProjectID: project.origin?.sourceProjectID, originRevisionID: project.origin?.sourceRevisionID
        ))
    }

    func insertRevision(_ draft: RevisionDraft) throws(StoreWriteError) {
        guard try revisionModel(draft.id) == nil else { throw .duplicateRevision(draft.id) }
        guard try projectModel(draft.projectID) != nil else { throw .missingProject(draft.projectID) }
        let projectID = draft.projectID, sequence = draft.sequence
        let sameSequence = FetchDescriptor<SchemaV1.RevisionModel>(
            predicate: #Predicate { $0.projectID == projectID && $0.sequence == sequence }
        )
        guard try count(sameSequence) == 0 else { throw .duplicateSequence(projectID: projectID, sequence: sequence) }
        let data: Data
        do {
            data = try SnapshotCodec.encode(draft.snapshot)
        } catch {
            throw .snapshotEncodingFailed
        }
        let (cause, source) = Self.encode(draft.cause)
        context.insert(SchemaV1.RevisionModel(
            id: draft.id, projectID: draft.projectID, sequence: draft.sequence, recordedAt: draft.recordedAt,
            cause: cause, restoredFromRevisionID: source, projectName: draft.snapshot.projectName,
            snapshotSchemaVersion: SnapshotCodec.currentSchemaVersion, snapshotData: data
        ))
    }

    func insert(_ reference: ResourceReferenceRecord) throws(StoreWriteError) {
        guard try referenceModel(reference.id) == nil else { throw .duplicateReference(reference.id) }
        context.insert(SchemaV1.ResourceReferenceModel(
            id: reference.id, initialPath: reference.initialPath, kind: Self.encode(reference.kind),
            bookmarkData: reference.bookmarkData, lastResolvedPath: reference.lastResolvedPath
        ))
    }

    func insert(_ checkpoint: CheckpointRecord) throws(StoreWriteError) {
        guard try checkpointModel(checkpoint.id) == nil else { throw .duplicateCheckpoint(checkpoint.id) }
        guard try revisionModel(checkpoint.revisionID) != nil else { throw .missingRevision(checkpoint.revisionID) }
        let model = SchemaV1.CheckpointModel(
            id: checkpoint.id, revisionID: checkpoint.revisionID, title: checkpoint.title,
            progressNote: checkpoint.progressNote, nextSteps: checkpoint.nextSteps, createdAt: checkpoint.createdAt
        )
        context.insert(model)
        model.attachments = checkpoint.attachments.enumerated().map { order, attachment in
            SchemaV1.AttachmentModel(
                id: attachment.id, relativePath: attachment.relativePath, mediaType: attachment.mediaType,
                byteCount: attachment.byteCount, order: order
            )
        }
    }

    // MARK: 운영 정보 갱신

    func updateReference(_ id: UUID, bookmarkData: Data, lastResolvedPath: String?) throws(StoreWriteError) {
        guard let model = try referenceModel(id) else { throw .missingReference(id) }
        model.bookmarkData = bookmarkData
        model.lastResolvedPath = lastResolvedPath
    }

    func updateProject(_ id: UUID, currentRevisionID: UUID, archivedAt: Date?) throws(StoreWriteError) {
        guard let model = try projectModel(id) else { throw .missingProject(id) }
        model.currentRevisionID = currentRevisionID
        model.archivedAt = archivedAt
    }

    func save() throws {
        try context.save()
    }

    // MARK: 읽기

    func projects() throws(StoreReadError) -> [ProjectRecord] {
        try read(FetchDescriptor<SchemaV1.ProjectModel>(sortBy: [SortDescriptor(\.createdAt)])).map(Self.record)
    }

    func project(_ id: UUID) throws(StoreReadError) -> ProjectRecord? {
        try read(FetchDescriptor<SchemaV1.ProjectModel>(predicate: #Predicate { $0.id == id })).first.map(Self.record)
    }

    /// 프로젝트의 revision 목록 정보를 순번 순서로. 스냅샷은 디코딩하지 않는다.
    func revisionSummaries(projectID: UUID) throws(StoreReadError) -> [RevisionSummary] {
        try read(FetchDescriptor<SchemaV1.RevisionModel>(
            predicate: #Predicate { $0.projectID == projectID }, sortBy: [SortDescriptor(\.sequence)]
        )).map(Self.summary)
    }

    func revisionSummary(_ id: UUID) throws(StoreReadError) -> RevisionSummary? {
        try read(FetchDescriptor<SchemaV1.RevisionModel>(predicate: #Predicate { $0.id == id })).first.map(Self.summary)
    }

    func snapshot(revisionID id: UUID) throws(StoreReadError) -> ConfigurationSnapshot {
        guard let model = try read(FetchDescriptor<SchemaV1.RevisionModel>(predicate: #Predicate { $0.id == id })).first else {
            throw .notFound(id)
        }
        do {
            return try SnapshotCodec.decode(model.snapshotData)
        } catch {
            throw .snapshot(error)
        }
    }

    func reference(_ id: UUID) throws(StoreReadError) -> ResourceReferenceRecord? {
        try read(FetchDescriptor<SchemaV1.ResourceReferenceModel>(predicate: #Predicate { $0.id == id })).first.map(Self.record)
    }

    func checkpoints(revisionID: UUID) throws(StoreReadError) -> [CheckpointRecord] {
        try read(FetchDescriptor<SchemaV1.CheckpointModel>(
            predicate: #Predicate { $0.revisionID == revisionID }, sortBy: [SortDescriptor(\.createdAt)]
        )).map(Self.record)
    }

    // MARK: 조회 도우미

    private func projectModel(_ id: UUID) throws(StoreWriteError) -> SchemaV1.ProjectModel? {
        try fetchForWrite(FetchDescriptor<SchemaV1.ProjectModel>(predicate: #Predicate { $0.id == id }))
    }

    private func revisionModel(_ id: UUID) throws(StoreWriteError) -> SchemaV1.RevisionModel? {
        try fetchForWrite(FetchDescriptor<SchemaV1.RevisionModel>(predicate: #Predicate { $0.id == id }))
    }

    private func referenceModel(_ id: UUID) throws(StoreWriteError) -> SchemaV1.ResourceReferenceModel? {
        try fetchForWrite(FetchDescriptor<SchemaV1.ResourceReferenceModel>(predicate: #Predicate { $0.id == id }))
    }

    private func checkpointModel(_ id: UUID) throws(StoreWriteError) -> SchemaV1.CheckpointModel? {
        try fetchForWrite(FetchDescriptor<SchemaV1.CheckpointModel>(predicate: #Predicate { $0.id == id }))
    }

    private func fetchForWrite<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws(StoreWriteError) -> Model? {
        do {
            return try context.fetch(descriptor).first
        } catch {
            throw .storeUnavailable
        }
    }

    private func count<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws(StoreWriteError) -> Int {
        do {
            return try context.fetchCount(descriptor)
        } catch {
            throw .storeUnavailable
        }
    }

    private func read<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws(StoreReadError) -> [Model] {
        do {
            return try context.fetch(descriptor)
        } catch {
            throw .storeUnavailable
        }
    }

    // MARK: 변환

    private static func record(_ model: SchemaV1.ProjectModel) throws(StoreReadError) -> ProjectRecord {
        let origin: ProjectOrigin?
        switch (model.originKind, model.originProjectID, model.originRevisionID) {
        case (nil, nil, nil):
            origin = nil
        case let (.some(kind), .some(project), .some(revision)):
            guard let kind = ProjectOrigin.Kind(rawValue: kind) else { throw .damagedRecord(model.id) }
            origin = ProjectOrigin(kind: kind, sourceProjectID: project, sourceRevisionID: revision)
        default:
            throw .damagedRecord(model.id)
        }
        return ProjectRecord(
            id: model.id, createdAt: model.createdAt, currentRevisionID: model.currentRevisionID,
            archivedAt: model.archivedAt, origin: origin
        )
    }

    private static func summary(_ model: SchemaV1.RevisionModel) throws(StoreReadError) -> RevisionSummary {
        guard let cause = decode(model.cause, source: model.restoredFromRevisionID) else { throw .damagedRecord(model.id) }
        return RevisionSummary(
            id: model.id, projectID: model.projectID, sequence: model.sequence,
            recordedAt: model.recordedAt, cause: cause, projectName: model.projectName
        )
    }

    private static func record(_ model: SchemaV1.ResourceReferenceModel) throws(StoreReadError) -> ResourceReferenceRecord {
        guard let kind = decodeKind(model.kind) else { throw .damagedRecord(model.id) }
        return ResourceReferenceRecord(
            id: model.id, initialPath: model.initialPath, kind: kind,
            bookmarkData: model.bookmarkData, lastResolvedPath: model.lastResolvedPath
        )
    }

    private static func record(_ model: SchemaV1.CheckpointModel) -> CheckpointRecord {
        CheckpointRecord(
            id: model.id, revisionID: model.revisionID, title: model.title, progressNote: model.progressNote,
            nextSteps: model.nextSteps, createdAt: model.createdAt,
            attachments: model.attachments.sorted { $0.order < $1.order }.map {
                AttachmentRecord(id: $0.id, relativePath: $0.relativePath, mediaType: $0.mediaType, byteCount: $0.byteCount)
            }
        )
    }

    private static func encode(_ cause: RevisionCause) -> (String, UUID?) {
        switch cause {
        case .created: ("created", nil)
        case let .edited(kind): (kind.rawValue, nil)
        case let .restored(source): ("restored", source)
        case .duplicated: ("duplicated", nil)
        case .imported: ("imported", nil)
        }
    }

    /// 복원 출처는 restored에만 있어야 한다(0005). 어긋나거나 모르는 값이면 nil.
    private static func decode(_ cause: String, source: UUID?) -> RevisionCause? {
        switch (cause, source) {
        case let ("restored", .some(source)): return .restored(from: source)
        case (_, .some), ("restored", nil): return nil
        case ("created", nil): return .created
        case ("duplicated", nil): return .duplicated
        case ("imported", nil): return .imported
        default: return RevisionCause.EditKind(rawValue: cause).map { .edited($0) }
        }
    }

    private static func encode(_ kind: LinkedTarget.Kind) -> String {
        switch kind {
        case .file: "file"
        case .folder: "folder"
        }
    }

    private static func decodeKind(_ value: String) -> LinkedTarget.Kind? {
        switch value {
        case "file": .file
        case "folder": .folder
        default: nil
        }
    }
}
