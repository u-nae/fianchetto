import Foundation

/// 연결 대상 변경 확인 정보. 판정은 보여 주기 위한 것이며 저장하지 않는다(0004).
struct ReplacementPreview: Equatable, Sendable {
    var projectID: UUID
    var nodeID: UUID
    var kind: LinkedTarget.Kind
    /// 기존 기록 당시 경로.
    var oldPath: String
    var newURL: URL
    var newPath: String
    var identity: TargetIdentity

    /// 판정 불가면 확정 시 교체로 기록된다고 알린다(PRD §6-B).
    var willRecordAsReplacement: Bool { identity == .undetermined }
}

enum ReplacementRejection: Error, Equatable, Sendable {
    case commit(CommitRejection)
    /// 새 대상에 연결할 수 없다.
    case unreachableTarget
}

/// 다시 선택(W15) 결과.
enum ReselectOutcome: Equatable, Sendable {
    /// 같은 대상이라 같은 참조의 접근 정보만 새로 저장했다. revision은 없다.
    case recovered
    /// 다른 대상이거나 같은지 알 수 없다. 연결 대상 변경 확인으로 넘긴다.
    case needsConfirmation(ReplacementPreview)
    case rejected(ReplacementRejection)
}

/// 과거 화면의 다시 선택 결과(W18, PRD §6-H). 다른 대상으로 덮어쓰지 않는다.
enum PastReselectOutcome: Equatable, Sendable {
    /// 같은 대상이라 그 참조의 접근 정보만 갱신했다(revision 없음, 0012).
    case recovered
    /// 다른 대상이거나 판정할 수 없다. 아무것도 바꾸지 않았다.
    case notSameTarget
    case rejected(ReplacementRejection)
}

enum ReplacementOutcome: Equatable, Sendable {
    case committed(RevisionSummary, ConfigurationSnapshot)
    case unchanged
    case rejected(ReplacementRejection)
}

/// Bishop의 이름·UUID·배치를 유지한 채 실제 대상만 바꾼다. 확인과 확정 모두 같은 대상인지 판정하고(0004),
/// 확정은 새 참조와 replaceTarget revision 하나를 커밋한다(W05). 대상 파일을 바꾸지 않는다.
/// 거부 순서: project_not_found → archived → 항목(node_not_found·not_linked_item·target_kind_mismatch) → unreachable_target → 커밋.
struct TargetReplacementService: Sendable {
    let bookmarks: BookmarkAdapter
    let configuration: ConfigurationService

    func preview(
        projectID: UUID, nodeID: UUID, newURL: URL
    ) async throws(ConfigurationServiceError) -> Result<ReplacementPreview, ReplacementRejection> {
        let node: ConfigurationNode
        switch try await linkedNode(projectID: projectID, nodeID: nodeID) {
        case let .success(found): node = found
        case let .failure(rejection): return .failure(rejection)
        }
        let kind: LinkedTarget.Kind
        do {
            kind = try bookmarks.kind(of: newURL)
        } catch {
            return .failure(.unreachableTarget)
        }
        guard kind.nodeKind == node.kind else { return .failure(.commit(.edit(.targetKindMismatch))) }
        return .success(ReplacementPreview(
            projectID: projectID, nodeID: nodeID, kind: kind, oldPath: node.recordedPath ?? "",
            newURL: newURL, newPath: newURL.standardizedFileURL.path,
            identity: try await identity(of: node, newURL: newURL)
        ))
    }

    /// 확정 시점의 상태로 다시 검사하고 같은 대상인지 다시 판정해 커밋한다.
    func confirm(_ preview: ReplacementPreview) async throws(ConfigurationServiceError) -> ReplacementOutcome {
        let node: ConfigurationNode
        switch try await linkedNode(projectID: preview.projectID, nodeID: preview.nodeID) {
        case let .success(found): node = found
        case let .failure(rejection): return .rejected(rejection)
        }
        guard preview.kind.nodeKind == node.kind else { return .rejected(.commit(.edit(.targetKindMismatch))) }
        let creation: BookmarkCreation
        do {
            creation = try bookmarks.createBookmark(for: preview.newURL)
        } catch {
            return .rejected(.unreachableTarget)
        }
        guard creation.kind == preview.kind else { return .rejected(.commit(.edit(.targetKindMismatch))) }
        let identity = try await identity(of: node, newURL: preview.newURL)

        let outcome = try await configuration.apply(
            .replaceTarget(preview.nodeID, kind: creation.kind, path: creation.path, identity: identity),
            to: preview.projectID, access: [creation.bookmarkData]
        )
        return switch outcome {
        case let .committed(summary, snapshot): .committed(summary, snapshot)
        case .unchanged: .unchanged
        case let .rejected(reason): .rejected(.commit(reason))
        }
    }

    /// 다시 선택: 같은 대상이면 접근을 복구하고(보관된 Board 포함, Q-W15-1), 아니면 연결 대상 변경 확인으로 넘긴다.
    /// 보관된 Board에서 다른 대상·판정 불가면 archived로 거부한다(0009). 접근 복구 저장이 실패하면 saveFailed를 던진다.
    func reselect(
        projectID: UUID, nodeID: UUID, newURL: URL
    ) async throws(ConfigurationServiceError) -> ReselectOutcome {
        let node: ConfigurationNode
        let archived: Bool
        switch try await linkedNode(projectID: projectID, nodeID: nodeID, allowArchived: true) {
        case let .success(found): (node, archived) = found
        case let .failure(rejection): return .rejected(rejection)
        }
        let kind: LinkedTarget.Kind
        do {
            kind = try bookmarks.kind(of: newURL)
        } catch {
            return .rejected(.unreachableTarget)
        }
        guard kind.nodeKind == node.kind else { return .rejected(.commit(.edit(.targetKindMismatch))) }
        let identity = try await identity(of: node, newURL: newURL)
        guard identity == .sameTarget else {
            if archived { return .rejected(.commit(.archived)) }
            return .needsConfirmation(ReplacementPreview(
                projectID: projectID, nodeID: nodeID, kind: kind, oldPath: node.recordedPath ?? "",
                newURL: newURL, newPath: newURL.standardizedFileURL.path, identity: identity
            ))
        }
        guard let referenceID = node.referenceID else { return .rejected(.commit(.edit(.notLinkedItem))) }
        let creation: BookmarkCreation
        do {
            creation = try bookmarks.createBookmark(for: newURL)
        } catch {
            return .rejected(.unreachableTarget)
        }
        do {
            try await configuration.store.updateReferenceAccess(referenceID, bookmarkData: creation.bookmarkData, lastResolvedPath: creation.path)
        } catch {
            throw .saveFailed
        }
        return .recovered
    }

    /// 과거 구성의 Bishop 다시 선택: 그 revision의 Node 참조와 같은 대상일 때만 접근 정보를 갱신한다(보관된 Board 포함).
    /// 다른 대상·판정 불가는 notSameTarget이며 확인 창으로 넘기지 않는다. 접근 정보 저장이 실패하면 saveFailed를 던진다.
    func reselectPast(node: ConfigurationNode, newURL: URL) async throws(ConfigurationServiceError) -> PastReselectOutcome {
        guard node.kind == .file || node.kind == .folder, let referenceID = node.referenceID else {
            return .rejected(.commit(.edit(.notLinkedItem)))
        }
        let kind: LinkedTarget.Kind
        do {
            kind = try bookmarks.kind(of: newURL)
        } catch {
            return .rejected(.unreachableTarget)
        }
        guard kind.nodeKind == node.kind else { return .rejected(.commit(.edit(.targetKindMismatch))) }
        guard try await identity(of: node, newURL: newURL) == .sameTarget else { return .notSameTarget }
        let creation: BookmarkCreation
        do {
            creation = try bookmarks.createBookmark(for: newURL)
        } catch {
            return .rejected(.unreachableTarget)
        }
        do {
            try await configuration.store.updateReferenceAccess(referenceID, bookmarkData: creation.bookmarkData, lastResolvedPath: creation.path)
        } catch {
            throw .saveFailed
        }
        return .recovered
    }

    // MARK: 내부

    private func linkedNode(
        projectID: UUID, nodeID: UUID
    ) async throws(ConfigurationServiceError) -> Result<ConfigurationNode, ReplacementRejection> {
        switch try await linkedNode(projectID: projectID, nodeID: nodeID, allowArchived: false) {
        case let .success(found): .success(found.node)
        case let .failure(rejection): .failure(rejection)
        }
    }

    private func linkedNode(
        projectID: UUID, nodeID: UUID, allowArchived: Bool
    ) async throws(ConfigurationServiceError) -> Result<(node: ConfigurationNode, archived: Bool), ReplacementRejection> {
        let store = configuration.store
        let project: ProjectRecord?
        do {
            project = try await store.project(projectID)
        } catch {
            throw .storeUnavailable
        }
        guard let project else { return .failure(.commit(.projectNotFound)) }
        guard allowArchived || project.archivedAt == nil else { return .failure(.commit(.archived)) }
        let snapshot: ConfigurationSnapshot
        do {
            snapshot = try await store.currentSnapshot(projectID: projectID)
        } catch {
            throw .currentConfigurationUnreadable
        }
        guard let node = snapshot.nodes.first(where: { $0.id == nodeID }) else { return .failure(.commit(.edit(.nodeNotFound))) }
        guard node.kind == .file || node.kind == .folder else { return .failure(.commit(.edit(.notLinkedItem))) }
        return .success((node, project.archivedAt != nil))
    }

    /// 기존 대상 식별자는 기존 참조의 북마크를 해석한 위치에서 구한다. 보안 범위 해석이 거부되면 식별자 확인용으로만 범위 없이
    /// 해석한다(0012). 둘 다 못 하면 식별자가 없는 것으로 본다(판정 불가).
    private func identity(of node: ConfigurationNode, newURL: URL) async throws(ConfigurationServiceError) -> TargetIdentity {
        var old = FileSystemIdentity(file: nil, volume: nil)
        if let referenceID = node.referenceID {
            let reference: ResourceReferenceRecord?
            do {
                reference = try await configuration.store.reference(referenceID)
            } catch {
                throw .storeUnavailable
            }
            if let reference, let url = bookmarks.identityURL(of: reference.bookmarkData) {
                old = bookmarks.identity(of: url)
            }
        }
        return TargetIdentityRule.identity(old: old, new: bookmarks.identity(of: newURL))
    }
}
