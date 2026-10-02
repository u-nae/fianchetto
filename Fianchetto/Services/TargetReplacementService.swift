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

    // MARK: 내부

    private func linkedNode(
        projectID: UUID, nodeID: UUID
    ) async throws(ConfigurationServiceError) -> Result<ConfigurationNode, ReplacementRejection> {
        let store = configuration.store
        let project: ProjectRecord?
        do {
            project = try await store.project(projectID)
        } catch {
            throw .storeUnavailable
        }
        guard let project else { return .failure(.commit(.projectNotFound)) }
        guard project.archivedAt == nil else { return .failure(.commit(.archived)) }
        let snapshot: ConfigurationSnapshot
        do {
            snapshot = try await store.currentSnapshot(projectID: projectID)
        } catch {
            throw .currentConfigurationUnreadable
        }
        guard let node = snapshot.nodes.first(where: { $0.id == nodeID }) else { return .failure(.commit(.edit(.nodeNotFound))) }
        guard node.kind == .file || node.kind == .folder else { return .failure(.commit(.edit(.notLinkedItem))) }
        return .success(node)
    }

    /// 기존 대상 식별자는 기존 참조의 북마크를 해석한 위치에서 구한다. 해석하지 못하면 식별자가 없는 것으로 본다(판정 불가).
    private func identity(of node: ConfigurationNode, newURL: URL) async throws(ConfigurationServiceError) -> TargetIdentity {
        var old = FileSystemIdentity(file: nil, volume: nil)
        if let referenceID = node.referenceID {
            let reference: ResourceReferenceRecord?
            do {
                reference = try await configuration.store.reference(referenceID)
            } catch {
                throw .storeUnavailable
            }
            if let reference, let resolved = try? bookmarks.resolve(reference.bookmarkData) {
                old = bookmarks.identity(of: resolved.url)
            }
        }
        return TargetIdentityRule.identity(old: old, new: bookmarks.identity(of: newURL))
    }
}
