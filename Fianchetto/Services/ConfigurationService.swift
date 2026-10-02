import Foundation

enum CommitRejection: Equatable, Sendable {
    case projectNotFound
    /// 보관된 Board는 편집할 수 없다(0005).
    case archived
    /// 북마크 바이트 수가 연결 대상 수와 맞지 않는다.
    case accessMismatch
    case blankName
    case edit(EditRejection)
}

enum ConfigurationCommitOutcome: Equatable, Sendable {
    /// 저장이 실제로 성공한 뒤에만 돌려준다.
    case committed(RevisionSummary, ConfigurationSnapshot)
    case unchanged
    case rejected(CommitRejection)
}

enum ConfigurationServiceError: Error, Equatable, Sendable {
    case saveFailed
    case currentConfigurationUnreadable
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
        }
    }

    // MARK: 판단 (ProjectStore actor 안에서 실행)

    enum Decision: Sendable {
        case outcome(ConfigurationCommitOutcome)
        case unreadableCurrent
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
        }
    }

    private static func map(_ error: ProjectStoreError) -> ConfigurationServiceError {
        switch error {
        case .saveFailed: .saveFailed
        case .storeUnavailable: .storeUnavailable
        }
    }
}
