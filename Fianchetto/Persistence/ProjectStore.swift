import Foundation
import SwiftData

/// 커밋 판단에 쓰는 프로젝트의 현재 상태.
struct ProjectState: Sendable {
    var project: ProjectRecord
    var latestSequence: Int
    /// 현재 revision의 스냅샷. 읽거나 디코딩하지 못하면 실패다(빈 구성으로 대신하지 않는다).
    var current: Result<ConfigurationSnapshot, StoreReadError>
}

/// 한 저장 단위로 추가할 revision과, 그 revision이 새로 쓰는 참조 레코드.
struct RevisionAppend: Sendable {
    var id: UUID
    var recordedAt: Date
    var cause: RevisionCause
    var snapshot: ConfigurationSnapshot
    var references: [ResourceReferenceRecord]
}

enum AppendDecision<Skip: Sendable>: Sendable {
    case append(RevisionAppend)
    case skip(Skip)
}

enum AppendResult<Skip: Sendable>: Sendable {
    case appended(RevisionSummary, RevisionAppend)
    case skipped(Skip)
    case projectNotFound
}

enum ProjectStoreError: Error, Equatable, Sendable {
    case saveFailed
    case storeUnavailable
}

/// 저장소 하나를 소유하는 actor. 커밋은 판단부터 저장까지 대기 지점 없이 실행되므로 요청이 하나씩 처리된다(PRD §7 직렬화).
/// 새 revision 추가, 현재 revision 이동, 새 참조 레코드를 한 번의 저장으로 커밋하고, 실패하면 모두 되돌린다(불변식 5).
@ModelActor
actor ProjectStore {
    /// 모든 변경을 저장 단위에 올린 뒤 저장 직전에 부르는 실패 지점(테스트 주입용).
    private var beforeSave: @Sendable () throws -> Void = {}

    init(container: ModelContainer, beforeSave: @escaping @Sendable () throws -> Void = {}) {
        modelContainer = container
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        self.beforeSave = beforeSave
    }

    private var adapter: StoreAdapter { StoreAdapter(context: modelContext) }

    // MARK: 커밋

    func createProject(_ project: ProjectRecord, first: RevisionAppend) throws(ProjectStoreError) -> RevisionSummary {
        do {
            try adapter.insert(project)
            try insert(first, projectID: project.id, sequence: 1)
        } catch {
            modelContext.rollback()
            throw .storeUnavailable
        }
        try commit()
        return Self.summary(first, projectID: project.id, sequence: 1)
    }

    /// 현재 상태로 `decide`를 실행하고, 추가하기로 하면 다음 순번 revision으로 커밋한다.
    func appendRevision<Skip: Sendable>(
        to projectID: UUID,
        decide: @Sendable (ProjectState) -> AppendDecision<Skip>
    ) throws(ProjectStoreError) -> AppendResult<Skip> {
        let adapter = self.adapter
        let project: ProjectRecord
        let latest: Int
        do {
            guard let found = try adapter.project(projectID) else { return .projectNotFound }
            project = found
            latest = try adapter.latestSequence(projectID: projectID) ?? 0
        } catch {
            throw .storeUnavailable
        }
        let current = Result { () throws(StoreReadError) -> ConfigurationSnapshot in
            try adapter.snapshot(revisionID: project.currentRevisionID)
        }

        switch decide(ProjectState(project: project, latestSequence: latest, current: current)) {
        case let .skip(value):
            return .skipped(value)
        case let .append(append):
            let sequence = latest + 1
            do {
                try insert(append, projectID: projectID, sequence: sequence)
                try adapter.updateProject(projectID, currentRevisionID: append.id, archivedAt: project.archivedAt)
            } catch {
                modelContext.rollback()
                throw .storeUnavailable
            }
            try commit()
            return .appended(Self.summary(append, projectID: projectID, sequence: sequence), append)
        }
    }

    /// 보관 상태는 목록 관리 정보라 revision을 만들지 않는다(0005).
    func setArchived(_ projectID: UUID, at date: Date?) throws(ProjectStoreError) {
        do {
            guard let project = try adapter.project(projectID) else { throw StoreWriteError.missingProject(projectID) }
            try adapter.updateProject(projectID, currentRevisionID: project.currentRevisionID, archivedAt: date)
        } catch {
            modelContext.rollback()
            throw .storeUnavailable
        }
        try commit()
    }

    // MARK: 읽기

    func projects() throws(StoreReadError) -> [ProjectRecord] {
        try adapter.projects()
    }

    func project(_ id: UUID) throws(StoreReadError) -> ProjectRecord? {
        try adapter.project(id)
    }

    /// Board 목록. 이름은 각 현재 revision의 목록 정보에서 읽고 스냅샷은 디코딩하지 않는다.
    func projectListings() throws(StoreReadError) -> [ProjectListing] {
        var listings: [ProjectListing] = []
        for project in try adapter.projects() {
            guard let current = try adapter.revisionSummary(project.currentRevisionID) else {
                throw .notFound(project.currentRevisionID)
            }
            listings.append(ProjectListing(
                id: project.id, name: current.projectName, createdAt: project.createdAt, archivedAt: project.archivedAt
            ))
        }
        return listings
    }

    func revisionSummaries(projectID: UUID) throws(StoreReadError) -> [RevisionSummary] {
        try adapter.revisionSummaries(projectID: projectID)
    }

    /// 한 revision의 구성. 선택한 revision만 디코딩한다(PRD §8 경량화).
    func snapshot(revisionID: UUID) throws(StoreReadError) -> ConfigurationSnapshot {
        try adapter.snapshot(revisionID: revisionID)
    }

    func currentSnapshot(projectID: UUID) throws(StoreReadError) -> ConfigurationSnapshot {
        guard let project = try adapter.project(projectID) else { throw .notFound(projectID) }
        return try adapter.snapshot(revisionID: project.currentRevisionID)
    }

    func reference(_ id: UUID) throws(StoreReadError) -> ResourceReferenceRecord? {
        try adapter.reference(id)
    }

    func referenceCount() throws(StoreReadError) -> Int {
        try adapter.referenceCount()
    }

    // MARK: 내부

    private func insert(_ append: RevisionAppend, projectID: UUID, sequence: Int) throws(StoreWriteError) {
        try adapter.insertRevision(RevisionDraft(
            id: append.id, projectID: projectID, sequence: sequence,
            recordedAt: append.recordedAt, cause: append.cause, snapshot: append.snapshot
        ))
        for reference in append.references {
            try adapter.insert(reference)
        }
    }

    /// 실패 지점과 저장. 실패하면 저장 단위의 모든 변경을 버려 다음 커밋에 섞이지 않게 한다.
    private func commit() throws(ProjectStoreError) {
        do {
            try beforeSave()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw .saveFailed
        }
    }

    private static func summary(_ append: RevisionAppend, projectID: UUID, sequence: Int) -> RevisionSummary {
        RevisionSummary(
            id: append.id, projectID: projectID, sequence: sequence,
            recordedAt: append.recordedAt, cause: append.cause, projectName: append.snapshot.projectName
        )
    }
}
