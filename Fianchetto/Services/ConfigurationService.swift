import Foundation

enum CommitRejection: Equatable, Sendable {
    case projectNotFound
    /// 보관된 Board는 편집할 수 없다(0005).
    case archived
    /// 북마크 바이트 수가 연결 대상 수와 맞지 않는다.
    case accessMismatch
    case blankName
    /// 복원 대상 revision이 없거나 다른 Board의 것이다.
    case revisionNotFound
    /// 체크포인트 제목이 비어 있다(W22).
    case blankTitle
    case edit(EditRejection)
}

enum ConfigurationCommitOutcome: Equatable, Sendable {
    /// 저장이 실제로 성공한 뒤에만 돌려준다.
    case committed(RevisionSummary, ConfigurationSnapshot)
    case unchanged
    case rejected(CommitRejection)
}

/// 체크포인트 저장 결과(W22). saved는 저장이 실제로 성공한 뒤에만 돌려준다.
enum CheckpointOutcome: Equatable, Sendable {
    case saved(CheckpointRecord)
    case rejected(CommitRejection)
}

enum ConfigurationServiceError: Error, Equatable, Sendable {
    case saveFailed
    case currentConfigurationUnreadable
    /// 복원 대상 revision의 구성을 읽을 수 없다(빈 구성으로 대신하지 않는다).
    case targetConfigurationUnreadable
    case storeUnavailable
}

/// 확정된 사용자 작업 하나를 현재 구성에 적용하고 changed 결과만 커밋한다.
/// 판단은 ProjectStore actor 안에서 실행되므로 같은 저장소의 요청은 하나씩 처리된다.
struct ConfigurationService: Sendable {
    let store: ProjectStore
    let now: @Sendable () -> Date
    let makeID: @Sendable () -> UUID

    func createProject(named name: String) async throws(ConfigurationServiceError) -> ConfigurationCommitOutcome {
        let projectName: String
        do {
            projectName = try ProjectName.normalize(name)
        } catch {
            return .rejected(.blankName)
        }
        let recordedAt = now()
        let projectID = makeID()
        let first = RevisionAppend(
            id: makeID(), recordedAt: recordedAt, cause: .created,
            snapshot: ConfigurationSnapshot(projectName: projectName, nodes: []), references: []
        )
        let project = ProjectRecord(id: projectID, createdAt: recordedAt, currentRevisionID: first.id, archivedAt: nil, origin: nil)
        do {
            let summary = try await store.createProject(project, first: first)
            return .committed(summary, first.snapshot)
        } catch {
            throw Self.map(error)
        }
    }

    /// `access`는 연결 대상 추가의 대상마다, 대상 교체의 새 대상에 하나씩 주는 북마크 바이트다. 그 밖의 편집은 비어 있어야 한다.
    func apply(
        _ edit: ConfigurationEdit,
        to projectID: UUID,
        access: [Data] = []
    ) async throws(ConfigurationServiceError) -> ConfigurationCommitOutcome {
        let now = self.now, makeID = self.makeID
        let result: AppendResult<Decision>
        do {
            result = try await store.appendRevision(to: projectID) { state in
                Self.decide(edit, access: access, state: state, now: now, makeID: makeID)
            }
        } catch {
            throw Self.map(error)
        }
        switch result {
        case .projectNotFound:
            return .rejected(.projectNotFound)
        case let .appended(summary, append):
            return .committed(summary, append.snapshot)
        case let .skipped(.outcome(outcome)):
            return outcome
        case .skipped(.unreadableCurrent):
            throw .currentConfigurationUnreadable
        case .skipped(.unreadableTarget):
            throw .targetConfigurationUnreadable
        }
    }

    /// 과거 revision의 구성을 새 revision으로 복원한다. 판단은 저장소 actor 안에서 하므로 결과는 커밋 시점 기준이다.
    func restore(_ revisionID: UUID, in projectID: UUID) async throws(ConfigurationServiceError) -> ConfigurationCommitOutcome {
        let now = self.now, makeID = self.makeID
        let result: AppendResult<Decision>
        do {
            result = try await store.appendRevision(to: projectID, restoring: revisionID) { state in
                Self.decideRestore(state: state, now: now, makeID: makeID)
            }
        } catch {
            throw Self.map(error)
        }
        switch result {
        case .projectNotFound:
            return .rejected(.projectNotFound)
        case let .appended(summary, append):
            return .committed(summary, append.snapshot)
        case let .skipped(.outcome(outcome)):
            return outcome
        case .skipped(.unreadableCurrent):
            throw .currentConfigurationUnreadable
        case .skipped(.unreadableTarget):
            throw .targetConfigurationUnreadable
        }
    }

    /// 과거 revision의 구성으로 새 Board를 만든다(W21, 결정표 duplicate_request_outcome). 판단과 커밋은 저장소 actor 안에서 한다.
    func duplicateProject(
        from revisionID: UUID, of sourceProjectID: UUID, named name: String
    ) async throws(ConfigurationServiceError) -> ConfigurationCommitOutcome {
        let now = self.now, makeID = self.makeID
        let result: DuplicationResult<Decision>
        do {
            result = try await store.createProject(copying: revisionID, of: sourceProjectID) { source in
                Self.decideDuplicate(named: name, source: source, now: now, makeID: makeID)
            }
        } catch {
            throw Self.map(error)
        }
        switch result {
        case let .created(summary, first):
            return .committed(summary, first.snapshot)
        case let .skipped(.outcome(outcome)):
            return outcome
        case .skipped(.unreadableCurrent):
            throw .currentConfigurationUnreadable
        case .skipped(.unreadableTarget):
            throw .targetConfigurationUnreadable
        }
    }

    /// 고정한 revision에 체크포인트를 붙인다(W22, 결정표 checkpoint_request_outcome). 판단과 커밋은 저장소 actor 안에서 한다.
    func saveCheckpoint(
        title: String, progressNote: String, nextSteps: String, on revisionID: UUID, in projectID: UUID
    ) async throws(ConfigurationServiceError) -> CheckpointOutcome {
        let now = self.now, makeID = self.makeID
        let result: CheckpointResult<CommitRejection>
        do {
            result = try await store.saveCheckpoint(on: revisionID, of: projectID) { source in
                Self.decideCheckpoint(
                    title: title, progressNote: progressNote, nextSteps: nextSteps, source: source, now: now, makeID: makeID
                )
            }
        } catch {
            throw Self.map(error)
        }
        switch result {
        case let .saved(record): return .saved(record)
        case let .skipped(rejection): return .rejected(rejection)
        }
    }

    // MARK: 판단 (ProjectStore actor 안에서 실행)

    enum Decision: Sendable {
        case outcome(ConfigurationCommitOutcome)
        case unreadableCurrent
        case unreadableTarget
    }

    /// 거부 순서: project_not_found(저장소) → archived → 대상 revision → 현재 구성 읽기 → 같음 → restored.
    /// 복원은 기록된 참조를 그대로 쓰므로 새 참조 레코드를 만들지 않는다.
    static func decideRestore(state: ProjectState, now: () -> Date, makeID: () -> UUID) -> AppendDecision<Decision> {
        if state.project.archivedAt != nil { return .skip(.outcome(.rejected(.archived))) }
        let summary: RevisionSummary
        let target: ConfigurationSnapshot
        switch state.restoreTarget {
        case nil, .notFound?, .otherProject?: return .skip(.outcome(.rejected(.revisionNotFound)))
        case .unreadable?: return .skip(.unreadableTarget)
        case let .found(foundSummary, snapshot)?: (summary, target) = (foundSummary, snapshot)
        }
        guard case let .success(current) = state.current else { return .skip(.unreadableCurrent) }
        if target == current { return .skip(.outcome(.unchanged)) }
        return .append(RevisionAppend(
            id: makeID(), recordedAt: now(), cause: .restored(from: summary.id), snapshot: target, references: []
        ))
    }

    /// 순서(FIRST): 이름 → 원본 Board → 원본 revision(없음·다른 Board / 읽기 실패) → 생성. 보관 상태는 읽지 않는다(PRD §6-C, 0009).
    /// 새 Board는 원본 참조 레코드를 그대로 쓰므로 참조를 만들지 않는다(0036). 만든 시각과 순번 1 기록 시각은 같은 `now()` 값이다.
    static func decideDuplicate(
        named name: String, source: DuplicationSource, now: () -> Date, makeID: () -> UUID
    ) -> DuplicationDecision<Decision> {
        let projectName: String
        do {
            projectName = try ProjectName.normalize(name)
        } catch {
            return .skip(.outcome(.rejected(.blankName)))
        }
        guard case let .found(sourceProject, target) = source else { return .skip(.outcome(.rejected(.projectNotFound))) }
        let summary: RevisionSummary
        let snapshot: ConfigurationSnapshot
        switch target {
        case .notFound, .otherProject: return .skip(.outcome(.rejected(.revisionNotFound)))
        case .unreadable: return .skip(.unreadableTarget)
        case let .found(foundSummary, foundSnapshot): (summary, snapshot) = (foundSummary, foundSnapshot)
        }
        let recordedAt = now()
        let projectID = makeID()
        let revisionID = makeID()
        let copy = ConfigurationDuplicator.duplicate(snapshot, projectName: projectName, makeID: makeID)
        let project = ProjectRecord(
            id: projectID, createdAt: recordedAt, currentRevisionID: revisionID, archivedAt: nil,
            origin: ProjectOrigin(kind: .duplicate, sourceProjectID: sourceProject.id, sourceRevisionID: summary.id)
        )
        let first = RevisionAppend(id: revisionID, recordedAt: recordedAt, cause: .duplicated, snapshot: copy, references: [])
        return .create(project, first: first)
    }

    /// 순서(FIRST): 제목(순수 검사) → Board → 보관(0009) → revision(없음·다른 Board) → 저장. 현재 revision 여부는 읽지 않는다(PRD §6-G 고정한 revision).
    /// 제목은 앞뒤 공백·줄바꿈을 정리하고, 메모·다음 할 일은 입력 그대로 둔다. 첨부는 비어 있다(W23).
    static func decideCheckpoint(
        title: String, progressNote: String, nextSteps: String, source: CheckpointSource, now: () -> Date, makeID: () -> UUID
    ) -> CheckpointDecision<CommitRejection> {
        let normalizedTitle: String
        do {
            normalizedTitle = try ProjectName.normalize(title)
        } catch {
            return .skip(.blankTitle)
        }
        guard case let .found(project, revision) = source else { return .skip(.projectNotFound) }
        if project.archivedAt != nil { return .skip(.archived) }
        switch revision {
        case .notFound, .otherProject: return .skip(.revisionNotFound)
        case let .found(summary):
            return .save(CheckpointRecord(
                id: makeID(), revisionID: summary.id, title: normalizedTitle, progressNote: progressNote,
                nextSteps: nextSteps, createdAt: now(), attachments: []
            ))
        }
    }

    /// 거부 순서: project_not_found(저장소) → archived → access_mismatch → 현재 구성 읽기 → 편집 결과.
    static func decide(
        _ edit: ConfigurationEdit,
        access: [Data],
        state: ProjectState,
        now: () -> Date,
        makeID: () -> UUID
    ) -> AppendDecision<Decision> {
        if state.project.archivedAt != nil { return .skip(.outcome(.rejected(.archived))) }
        guard access.count == expectedAccessCount(edit) else { return .skip(.outcome(.rejected(.accessMismatch))) }
        guard case let .success(current) = state.current else { return .skip(.unreadableCurrent) }

        switch ConfigurationEditor.apply(edit, to: current, makeID: makeID) {
        case .unchanged:
            return .skip(.outcome(.unchanged))
        case let .rejected(reason):
            return .skip(.outcome(.rejected(.edit(reason))))
        case let .changed(next):
            return .append(RevisionAppend(
                id: makeID(), recordedAt: now(), cause: .edited(editKind(edit)), snapshot: next,
                references: newReferences(edit, base: current, result: next, access: access)
            ))
        }
    }

    private static func expectedAccessCount(_ edit: ConfigurationEdit) -> Int {
        switch edit {
        case let .addLinkedItems(targets, _, _): targets.count
        case .replaceTarget: 1
        default: 0
        }
    }

    /// 커밋이 새로 쓰는 referenceID마다 참조 레코드를 만든다.
    /// 연결 대상 추가는 새 Node를 선택 순서대로 연속 삽입하므로(W03) 정렬 순서가 요청의 대상 순서와 같다.
    private static func newReferences(
        _ edit: ConfigurationEdit, base: ConfigurationSnapshot, result: ConfigurationSnapshot, access: [Data]
    ) -> [ResourceReferenceRecord] {
        let nodes: [ConfigurationNode]
        switch edit {
        case .addLinkedItems:
            let existing = Set(base.nodes.map(\.id))
            nodes = result.nodes.filter { !existing.contains($0.id) }.sorted { $0.sortIndex < $1.sortIndex }
        case let .replaceTarget(id, _, _, _):
            nodes = result.nodes.filter { $0.id == id }
        default:
            nodes = []
        }
        return zip(nodes, access).compactMap { node, bookmark in
            guard let id = node.referenceID, let path = node.recordedPath else { return nil }
            return ResourceReferenceRecord(
                id: id, initialPath: path, kind: node.kind == .file ? .file : .folder,
                bookmarkData: bookmark, lastResolvedPath: path
            )
        }
    }

    private static func editKind(_ edit: ConfigurationEdit) -> RevisionCause.EditKind {
        switch edit {
        case .renameProject: .renameProject
        case .addGroup: .addGroup
        case .addLinkedItems: .addLinkedItems
        case .addWebLink: .addWebLink
        case .renameNode: .renameNode
        case .changeURL: .changeURL
        case .move: .move
        case .remove: .remove
        case .replaceTarget: .replaceTarget
        case .changePurpose: .changePurpose
        }
    }

    private static func map(_ error: ProjectStoreError) -> ConfigurationServiceError {
        switch error {
        case .saveFailed: .saveFailed
        case .storeUnavailable: .storeUnavailable
        }
    }
}
