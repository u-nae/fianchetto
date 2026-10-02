import Foundation
import Testing
@testable import Fianchetto

@Suite("트리 끌기 항목 형식 (W12)")
struct TreeDragItemsTests {
    @Test("[W12-unknown-item-drop] 앱 안 항목 문자열은 식별자로 돌아오고 다른 문자열은 항목이 아니다")
    func roundTrip() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000042"))
        #expect(NodeDragItem.nodeID(from: NodeDragItem(nodeID: id).text) == id)
        #expect(NodeDragItem.nodeID(from: id.uuidString) == nil)
        #expect(NodeDragItem.nodeID(from: "fianchetto-node:") == nil)
        #expect(NodeDragItem.nodeID(from: "fianchetto-node:not-a-uuid") == nil)
        #expect(NodeDragItem.nodeID(from: "") == nil)
    }
}
