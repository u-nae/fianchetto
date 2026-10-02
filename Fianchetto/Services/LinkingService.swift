import Foundation

/// 고른 로컬 파일·폴더를 연결할 요청. 위치가 nil이면 부모의 끝이다.
struct LinkRequest: Equatable, Sendable {
    var projectID: UUID
    var parentID: UUID?
    var position: Int?
    var urls: [URL]
}

enum LinkRejection: Equatable, Sendable {
    /// 연결 정보를 만들지 못한 대상의 이름(선택 순서). 아무것도 연결하지 않았다.
    case unreachableTargets([String])
    case commit(CommitRejection)
}

enum LinkOutcome: Equatable, Sendable {
    case committed(RevisionSummary, ConfigurationSnapshot)
    case unchanged
    case rejected(LinkRejection)
}

/// 로컬 파일·폴더를 Bishop으로 연결한다. 대상마다 읽기 전용 북마크를 만들고, 모두 성공했을 때만 revision 하나로 커밋한다.
/// nonisolated async라 MainActor 밖에서 실행된다. 연결 대상을 이동·복사·수정·삭제하지 않는다.
struct LinkingService: Sendable {
    let bookmarks: BookmarkAdapter
    let configuration: ConfigurationService

    func link(_ request: LinkRequest) async throws(ConfigurationServiceError) -> LinkOutcome {
        guard !request.urls.isEmpty else { return .unchanged }
        // 북마크를 만들기 전에 Board 상태를 확인해, 바꿀 수 없는 Board에는 대상 접근을 시작하지 않는다.
        let project: ProjectRecord?
        do {
            project = try await configuration.store.project(request.projectID)
        } catch {
            throw .storeUnavailable
        }
        guard let project else { return .rejected(.commit(.projectNotFound)) }
        guard project.archivedAt == nil else { return .rejected(.commit(.archived)) }

        var targets: [LinkedTarget] = []
        var access: [Data] = []
        var unreachable: [String] = []
        for url in request.urls {
            do {
                let creation = try bookmarks.createBookmark(for: url)
                targets.append(LinkedTarget(
                    displayName: URL(filePath: creation.path).lastPathComponent, kind: creation.kind, path: creation.path
                ))
                access.append(creation.bookmarkData)
            } catch {
                unreachable.append(url.lastPathComponent)
            }
        }
        guard unreachable.isEmpty else { return .rejected(.unreachableTargets(unreachable)) }

        let outcome = try await configuration.apply(
            .addLinkedItems(targets, parentID: request.parentID, position: request.position),
            to: request.projectID, access: access
        )
        return switch outcome {
        case let .committed(summary, snapshot): .committed(summary, snapshot)
        case .unchanged: .unchanged
        case let .rejected(reason): .rejected(.commit(reason))
        }
    }
}
