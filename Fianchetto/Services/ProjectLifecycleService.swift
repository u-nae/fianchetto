import Foundation

enum LifecycleOutcome: Equatable, Sendable {
    case changed
    /// 이미 요청한 상태다. 보관 시각을 바꾸지 않는다.
    case unchanged
    case rejected(CommitRejection)
}

/// Board 보관·보관 해제. 목록 관리 정보라 revision을 만들지 않는다(PRD §6-C, 0005). 보관된 Board는 읽기 전용이다(0009).
struct ProjectLifecycleService: Sendable {
    let store: ProjectStore
    let now: @Sendable () -> Date

    func setArchived(_ projectID: UUID, _ archived: Bool) async throws(ConfigurationServiceError) -> LifecycleOutcome {
        let project: ProjectRecord?
        do {
            project = try await store.project(projectID)
        } catch {
            throw .storeUnavailable
        }
        guard let project else { return .rejected(.projectNotFound) }
        guard (project.archivedAt != nil) != archived else { return .unchanged }
        do {
            try await store.setArchived(projectID, at: archived ? now() : nil)
        } catch {
            throw error == .saveFailed ? .saveFailed : .storeUnavailable
        }
        return .changed
    }
}
