import Foundation
import SwiftData

/// 복원 대상 revision을 저장소에서 읽은 결과.
enum RestoreTarget: Equatable, Sendable {
    case found(RevisionSummary, ConfigurationSnapshot)
    case notFound
    /// 다른 Project의 revision이다.
    case otherProject
    /// revision은 있지만 구성을 읽거나 디코딩하지 못한다.
    case unreadable
}

/// 커밋 판단에 쓰는 프로젝트의 현재 상태.
struct ProjectState: Sendable {
    var project: ProjectRecord
    var latestSequence: Int
    /// 현재 revision의 스냅샷. 읽거나 디코딩하지 못하면 실패다(빈 구성으로 대신하지 않는다).
    var current: Result<ConfigurationSnapshot, StoreReadError>
    /// `appendRevision(to:restoring:)`에 대상을 주었을 때만 채워진다.
    var restoreTarget: RestoreTarget? = nil
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

/// 복제 원본을 저장소에서 읽은 결과(W21). revision 읽기 결과는 복원과 같은 네 경우(RestoreTarget)다.
enum DuplicationSource: Sendable {
    case projectNotFound
    case found(ProjectRecord, RestoreTarget)
}

enum DuplicationDecision<Skip: Sendable>: Sendable {
    case create(ProjectRecord, first: RevisionAppend)
    case skip(Skip)
}

enum DuplicationResult<Skip: Sendable>: Sendable {
    case created(RevisionSummary, RevisionAppend)
    case skipped(Skip)
}

/// 체크포인트를 붙일 revision을 저장소에서 읽은 결과(W22). 스냅샷은 읽지 않는다.
enum CheckpointRevision: Equatable, Sendable {
    case found(RevisionSummary)
    case notFound
    /// 다른 Project의 revision이다.
    case otherProject
}

enum CheckpointSource: Sendable {
    case projectNotFound
    case found(ProjectRecord, CheckpointRevision)
}

enum CheckpointDecision<Skip: Sendable>: Sendable {
    case save(CheckpointRecord)
    case skip(Skip)
}

enum CheckpointResult<Skip: Sendable>: Sendable {
    case saved(CheckpointRecord)
    case skipped(Skip)
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

    /// 원본 Board와 revision을 같은 actor 안에서 읽어 `decide`에 주고, 만들기로 하면 새 Project와 순번 1 revision을
    /// 한 저장 단위로 커밋한다(W21, 불변식 5). 참조 레코드는 만들지 않는다(0036).
    func createProject<Skip: Sendable>(
        copying sourceRevisionID: UUID, of sourceProjectID: UUID,
        decide: @Sendable (DuplicationSource) -> DuplicationDecision<Skip>
    ) throws(ProjectStoreError) -> DuplicationResult<Skip> {
        let source: DuplicationSource
        do {
            if let project = try adapter.project(sourceProjectID) {
                source = .found(project, readRestoreTarget(sourceRevisionID, projectID: sourceProjectID))
            } else {
                source = .projectNotFound
            }
        } catch {
            throw .storeUnavailable
        }
        switch decide(source) {
        case let .skip(value):
            return .skipped(value)
        case let .create(project, first):
            do {
                try adapter.insert(project)
                try insert(first, projectID: project.id, sequence: 1)
            } catch {
                modelContext.rollback()
                throw .storeUnavailable
            }
            try commit()
            return .created(Self.summary(first, projectID: project.id, sequence: 1), first)
        }
    }

    /// Board와 revision을 같은 actor 안에서 읽어 `decide`에 주고, 저장하기로 하면 체크포인트 하나를 한 저장 단위로 커밋한다.
    /// revision을 만들지 않고 currentRevisionID를 옮기지 않는다(PRD §6-G, A10).
    func saveCheckpoint<Skip: Sendable>(
        on revisionID: UUID, of projectID: UUID,
        decide: @Sendable (CheckpointSource) -> CheckpointDecision<Skip>
    ) throws(ProjectStoreError) -> CheckpointResult<Skip> {
        let source: CheckpointSource
        do {
            if let project = try adapter.project(projectID) {
                let revision: CheckpointRevision
                if let summary = try adapter.revisionSummary(revisionID) {
                    revision = summary.projectID == projectID ? .found(summary) : .otherProject
                } else {
                    revision = .notFound
                }
                source = .found(project, revision)
            } else {
                source = .projectNotFound
            }
        } catch {
            throw .storeUnavailable
        }
        switch decide(source) {
        case let .skip(value):
            return .skipped(value)
        case let .save(record):
            do {
                try adapter.insert(record)
            } catch {
                modelContext.rollback()
                throw .storeUnavailable
            }
            try commit()
            return .saved(record)
        }
    }

    /// 현재 상태로 `decide`를 실행하고, 추가하기로 하면 다음 순번 revision으로 커밋한다.
    /// `targetRevisionID`를 주면 판단 전에 그 revision을 같은 actor 안에서 읽어 `ProjectState.restoreTarget`에 싣는다.
    func appendRevision<Skip: Sendable>(
        to projectID: UUID,
        restoring targetRevisionID: UUID? = nil,
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

        let restoreTarget = targetRevisionID.map { readRestoreTarget($0, projectID: projectID) }
        switch decide(ProjectState(project: project, latestSequence: latest, current: current, restoreTarget: restoreTarget)) {
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

    private func readRestoreTarget(_ id: UUID, projectID: UUID) -> RestoreTarget {
        let summary: RevisionSummary
        do {
            guard let found = try adapter.revisionSummary(id) else { return .notFound }
            summary = found
        } catch {
            return .unreadable
        }
        guard summary.projectID == projectID else { return .otherProject }
        do {
            return .found(summary, try adapter.snapshot(revisionID: id))
        } catch {
            return .unreadable
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

    /// 같은 참조의 접근 정보(북마크)와 마지막 확인 위치만 바꾼다. 참조 식별자·처음 경로·revision은 그대로다(불변식 8).
    func updateReferenceAccess(_ id: UUID, bookmarkData: Data, lastResolvedPath: String?) throws(ProjectStoreError) {
        do {
            try adapter.updateReference(id, bookmarkData: bookmarkData, lastResolvedPath: lastResolvedPath)
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

    func revisionSummaries(projectID: UUID, below sequence: Int?, limit: Int) throws(StoreReadError) -> [RevisionSummary] {
        try adapter.revisionSummaries(projectID: projectID, below: sequence, limit: limit)
    }

    func revisionSummaries(projectID: UUID, sequences range: ClosedRange<Int>) throws(StoreReadError) -> [RevisionSummary] {
        try adapter.revisionSummaries(projectID: projectID, sequences: range)
    }

    func latestRevision(projectID: UUID, atOrBefore instant: Date) throws(StoreReadError) -> RevisionSummary? {
        try adapter.latestRevision(projectID: projectID, atOrBefore: instant)
    }

    func revisionSummary(_ id: UUID) throws(StoreReadError) -> RevisionSummary? {
        try adapter.revisionSummary(id)
    }

    /// 한 revision의 구성. 선택한 revision만 디코딩한다(PRD §8 경량화).
    func snapshot(revisionID: UUID) throws(StoreReadError) -> ConfigurationSnapshot {
        try adapter.snapshot(revisionID: revisionID)
    }

    func currentSnapshot(projectID: UUID) throws(StoreReadError) -> ConfigurationSnapshot {
        guard let project = try adapter.project(projectID) else { throw .notFound(projectID) }
        return try adapter.snapshot(revisionID: project.currentRevisionID)
    }

    /// 현재 revision의 목록 정보. Board가 없으면 nil. 체크포인트 시트를 열 때 revision을 고정하는 데 쓴다(W22).
    func currentRevisionSummary(projectID: UUID) throws(StoreReadError) -> RevisionSummary? {
        guard let project = try adapter.project(projectID) else { return nil }
        guard let summary = try adapter.revisionSummary(project.currentRevisionID) else { throw .notFound(project.currentRevisionID) }
        return summary
    }

    func checkpointSummaries(projectID: UUID) throws(StoreReadError) -> [CheckpointSummary] {
        try adapter.checkpointSummaries(projectID: projectID)
    }

    func checkpoint(_ id: UUID) throws(StoreReadError) -> CheckpointRecord? {
        try adapter.checkpoint(id)
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
