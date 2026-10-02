import Foundation

extension LinkStatus {
    init(_ cause: BookmarkFailureCause) {
        self = switch cause {
        case .accessDenied: .accessRequired
        case .missing: .missing
        case .volumeUnavailable: .volumeUnavailable
        case .checkFailed: .checkFailed
        }
    }
}

/// Bishop의 저장된 접근 정보를 해석해 연결 상태를 구한다. 선택·열기·명시적 새로고침 때만 부른다(PRD §8 경량화).
/// 해석 중 새 접근 정보가 만들어지면(stale·위치 변경) 같은 참조에 저장하고 revision은 만들지 않는다(불변식 8).
/// 그 저장이 실패해도 확인 결과는 그대로이며 다음 확인 때 다시 시도한다.
struct LinkStatusService: Sendable {
    let store: ProjectStore
    let bookmarks: BookmarkAdapter

    private static let log = AppLog.logger(.fileAccess)

    /// 연결 항목의 현재 위치. 해석은 호출한 곳(MainActor 밖)에서 한다.
    func resolve(_ node: ConfigurationNode) async -> Result<URL, BookmarkFailureCause> {
        guard let referenceID = node.referenceID, let reference = try? await store.reference(referenceID) else {
            return .failure(.checkFailed)
        }
        let resolution: BookmarkResolution
        do {
            resolution = try bookmarks.resolve(reference.bookmarkData)
        } catch {
            if case let .resolutionFailed(cause) = error {
                Self.log.notice("link check failed: \(String(describing: cause), privacy: .public)")
                return .failure(cause)
            }
            return .failure(.checkFailed)
        }
        if let refreshed = resolution.refreshedBookmark {
            do {
                try await store.updateReferenceAccess(referenceID, bookmarkData: refreshed, lastResolvedPath: resolution.url.path)
            } catch {
                Self.log.notice("access info refresh not saved")
            }
        }
        return .success(resolution.url)
    }

    /// Bishop 하나의 상태. 그룹·웹 링크·없는 항목이면 nil.
    func check(projectID: UUID, nodeID: UUID) async -> LinkStatus? {
        guard let snapshot = try? await store.currentSnapshot(projectID: projectID),
              let node = snapshot.nodes.first(where: { $0.id == nodeID }), node.kind == .file || node.kind == .folder
        else { return nil }
        return await status(of: node)
    }

    /// Board의 모든 Bishop을 한 번씩 확인한다.
    func checkAll(projectID: UUID) async -> [UUID: LinkStatus] {
        guard let snapshot = try? await store.currentSnapshot(projectID: projectID) else { return [:] }
        var result: [UUID: LinkStatus] = [:]
        for node in snapshot.nodes where node.kind == .file || node.kind == .folder {
            result[node.id] = await status(of: node)
        }
        return result
    }

    private func status(of node: ConfigurationNode) async -> LinkStatus {
        switch await resolve(node) {
        case .success: .healthy
        case let .failure(cause): LinkStatus(cause)
        }
    }
}
