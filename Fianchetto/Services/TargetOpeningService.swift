import Foundation

enum OpenCommand: Sendable {
    /// 기본 앱(웹 링크는 기본 브라우저)으로 연다.
    case open
    /// Finder에서 대상을 선택해 보여 준다. Bishop에만 있다.
    case reveal
}

enum OpenFailure: Error, Equatable, Sendable {
    /// 저장된 접근 정보로 대상을 찾지 못했다(W06 분류).
    case unreachable(BookmarkFailureCause)
    /// 기본 앱에 넘기지 못했다.
    case launchFailed
    /// 현재 구성을 읽지 못했다.
    case unreadable
}

enum OpenOutcome: Equatable, Sendable {
    case opened
    /// 그 항목에는 해당 명령이 없다(그룹, 웹 링크의 Finder 보기, 이미 없는 항목).
    case notApplicable
    case failed(OpenFailure)
}

/// Bishop의 현재 대상이나 웹 링크를 연다. 조회이므로 revision을 만들지 않고, 대상 파일을 바꾸지 않는다(PRD §7).
/// 저장된 접근 정보는 MainActor 밖에서 해석하고, 접근 범위를 연 상태로 launcher에 넘긴다.
/// 해석과 새 접근 정보 저장은 연결 상태 확인과 같은 경로(LinkStatusService)를 쓴다.
struct TargetOpeningService: Sendable {
    let store: ProjectStore
    let links: LinkStatusService
    let launcher: any TargetLauncher
    /// 해석한 위치의 접근 범위. 기본은 그 URL 자신이고, 테스트는 시작·종료를 기록하는 대역을 넣는다.
    var accessScope: @Sendable (URL) -> any SecurityScopedResource & Sendable = { $0 }

    private static let log = AppLog.logger(.fileAccess)

    func perform(_ command: OpenCommand, projectID: UUID, nodeID: UUID) async -> OpenOutcome {
        let snapshot: ConfigurationSnapshot
        do {
            snapshot = try await store.currentSnapshot(projectID: projectID)
        } catch {
            return .failed(.unreadable)
        }
        guard let node = snapshot.nodes.first(where: { $0.id == nodeID }) else { return .notApplicable }
        return await perform(command, node: node)
    }

    /// 주어진 Node를 연다. 과거 구성의 항목은 그 revision의 Node를 넘긴다: Bishop은 그 참조가 지금 해석하는 대상,
    /// 웹 링크는 당시 URL을 연다(PRD §6-D, 0003). 현재 구성을 다시 읽지 않는다.
    func perform(_ command: OpenCommand, node: ConfigurationNode) async -> OpenOutcome {
        switch (node.kind, command) {
        case (.group, _), (.webLink, .reveal):
            return .notApplicable
        case (.webLink, .open):
            guard let url = node.url.flatMap(URL.init(string:)) else { return .failed(.launchFailed) }
            let launcher = launcher
            let launched = await MainActor.run { launcher.open(url) }
            return launched ? .opened : .failed(.launchFailed)
        case (.file, _), (.folder, _):
            return await openLinked(node, command)
        }
    }

    private func openLinked(_ node: ConfigurationNode, _ command: OpenCommand) async -> OpenOutcome {
        let url: URL
        switch await links.resolve(node) {
        case let .success(resolved): url = resolved
        case let .failure(cause): return .failed(.unreachable(cause))
        }
        // 다른 앱에 넘기는 동안 접근 범위를 열어 둔다. 시작 결과와 상관없이 요청은 한 번 보내고, 종료는 시작이 성공했을 때만 한다.
        let launcher = launcher
        let scope = accessScope(url)
        let started = scope.startAccessingSecurityScopedResource()
        let launched = await MainActor.run { () -> Bool in
            switch command {
            case .open:
                return launcher.open(url)
            case .reveal:
                launcher.reveal(url)
                return true
            }
        }
        if started { scope.stopAccessingSecurityScopedResource() }
        if !launched { Self.log.notice("launch failed") }
        return launched ? .opened : .failed(.launchFailed)
    }
}
