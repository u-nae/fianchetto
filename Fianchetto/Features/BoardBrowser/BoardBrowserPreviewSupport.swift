#if DEBUG
import SwiftUI

/// Xcode Preview용 화면 상태 모델. 저장소를 열지 않으며(openStore는 항상 실패) 파일 선택·Finder·종료는 아무 일도 하지 않는다.
/// 식별자는 고정값이라 미리보기가 매번 같은 모습이다.
@MainActor
enum BoardBrowserPreviewSupport {
    enum Scenario: String, CaseIterable {
        /// 항목이 없는 Board.
        case emptyBoard
        /// 긴 Board·항목 이름과 깊은 중첩.
        case longNames
        /// 상태 4종(권한 필요·대상 없음·볼륨 연결 필요·확인 실패)과 정상이 섞인 트리.
        case mixedStatuses
    }

    static func model(_ scenario: Scenario) -> BoardBrowserModel {
        let model = BoardBrowserModel(dependencies: .init(
            storeURL: nil,
            openStore: { url throws(StoreOpenError) in throw StoreOpenError(category: .unavailable, url: url) },
            lastBoard: PreviewLastBoard(),
            revealInFinder: { _ in },
            quit: {},
            pickTargets: { nil },
            pickReplacement: { _ in nil }
        ))
        let created = Date(timeIntervalSinceReferenceDate: 812_000_000)
        let boards = [
            ProjectListing(id: id(1), name: scenario == .longNames ? "아주 긴 이름의 서비스 A 인증 리팩토링 Board" : "서비스 A", createdAt: created),
            ProjectListing(id: id(2), name: "디자인 시스템", createdAt: created),
            ProjectListing(id: id(3), name: "지난 분기 자료", createdAt: created, archivedAt: created),
        ]
        let (snapshot, statuses) = content(scenario, projectName: boards[0].name)
        model.loadPreview(boards: boards, selectedBoardID: id(1), snapshot: snapshot, statuses: statuses)
        return model
    }

    private static func content(_ scenario: Scenario, projectName: String) -> (ConfigurationSnapshot, [UUID: LinkStatus]) {
        switch scenario {
        case .emptyBoard:
            return (ConfigurationSnapshot(projectName: projectName, nodes: []), [:])
        case .longNames:
            return (ConfigurationSnapshot(projectName: projectName, nodes: [
                group(10, "개발", parent: nil, at: 0),
                group(11, "백엔드와 인증 서버 리팩토링 참고 자료 묶음", parent: 10, at: 0),
                group(12, "세 번째 단계로 깊게 중첩된 Wing", parent: 11, at: 0),
                file(13, "인증 토큰 갱신 흐름 설계 메모 최종본 v3 (검토 반영).md", parent: 12, at: 0),
                folder(14, "legacy-authentication-service-backend", parent: 11, at: 1),
                link(15, "API 명세 (내부 위키 · 인증 · 토큰 · 세션 관리)", parent: nil, at: 1),
            ]), [:])
        case .mixedStatuses:
            return (ConfigurationSnapshot(projectName: projectName, nodes: [
                group(20, "개발", parent: nil, at: 0),
                folder(21, "backend", parent: 20, at: 0),
                file(22, "설계 메모.md", parent: 20, at: 1),
                folder(23, "assets", parent: nil, at: 1),
                file(24, "회의록.md", parent: nil, at: 2),
                folder(25, "외장 디스크 자료", parent: nil, at: 3),
                link(26, "API 명세", parent: nil, at: 4),
            ]), [
                id(21): .healthy,
                id(22): .accessRequired,
                id(23): .missing,
                id(24): .checkFailed,
                id(25): .volumeUnavailable,
            ])
        }
    }

    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private static func group(_ n: Int, _ name: String, parent: Int?, at index: Int) -> ConfigurationNode {
        ConfigurationNode(id: id(n), kind: .group, displayName: name, parentID: parent.map(id), sortIndex: index)
    }

    private static func file(_ n: Int, _ name: String, parent: Int?, at index: Int) -> ConfigurationNode {
        ConfigurationNode(
            id: id(n), kind: .file, displayName: name, parentID: parent.map(id), sortIndex: index,
            referenceID: id(n + 1000), recordedPath: "/Users/preview/Documents/\(name)"
        )
    }

    private static func folder(_ n: Int, _ name: String, parent: Int?, at index: Int) -> ConfigurationNode {
        ConfigurationNode(
            id: id(n), kind: .folder, displayName: name, parentID: parent.map(id), sortIndex: index,
            referenceID: id(n + 1000), recordedPath: "/Users/preview/Developer/\(name)"
        )
    }

    private static func link(_ n: Int, _ name: String, parent: Int?, at index: Int) -> ConfigurationNode {
        ConfigurationNode(id: id(n), kind: .webLink, displayName: name, parentID: parent.map(id), sortIndex: index, url: "https://example.com/api")
    }
}

private final class PreviewLastBoard: LastBoardRecord {
    var lastBoardID: UUID?
}

#Preview("빈 Board") {
    BoardBrowserView(model: BoardBrowserPreviewSupport.model(.emptyBoard))
}

#Preview("긴 이름") {
    BoardBrowserView(model: BoardBrowserPreviewSupport.model(.longNames))
}

#Preview("연결 상태") {
    BoardBrowserView(model: BoardBrowserPreviewSupport.model(.mixedStatuses))
}

#Preview("연결 상태 · 다크") {
    BoardBrowserView(model: BoardBrowserPreviewSupport.model(.mixedStatuses))
        .preferredColorScheme(.dark)
}
#endif
