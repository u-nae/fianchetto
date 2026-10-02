import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("Xcode Preview용 화면 상태 (W15 개발 도구)")
struct BoardBrowserPreviewSupportTests {
    @Test("미리보기 모델은 저장소를 열지 않고 상태 4종과 정상이 섞인 트리를 보여 준다")
    func mixedStatuses() throws {
        let model = BoardBrowserPreviewSupport.model(.mixedStatuses)
        #expect(model.phase == .ready)
        #expect(model.openedStore == nil)
        let snapshot = try #require(model.loadedSnapshot)
        let shown = Set(snapshot.nodes.compactMap { model.displayedStatus(of: $0.id) })
        #expect(shown == [.accessRequired, .missing, .volumeUnavailable, .checkFailed])
        #expect(model.displayedStatus(of: try #require(snapshot.node(named: "backend")).id) == nil)
        #expect(model.archivedNames == ["지난 분기 자료"])
    }

    @Test("미리보기 시나리오는 빈 Board와 깊게 중첩된 긴 이름을 만든다")
    func otherScenarios() throws {
        #expect(BoardBrowserPreviewSupport.model(.emptyBoard).loadedSnapshot?.nodes.isEmpty == true)
        let long = BoardBrowserPreviewSupport.model(.longNames)
        #expect(long.tree.first?.children?.first?.children?.first?.children?.isEmpty == false)
    }
}
