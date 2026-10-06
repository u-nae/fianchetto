import Foundation
import Testing
@testable import Fianchetto

/// 비교 문구(W19): 이동 문구의 자리값과 '변경 내용' 위치 표기. 저장소 없이 비교 모델의 문구 함수만 확인한다.
@MainActor
@Suite("비교 문구(W19)")
struct ComparisonTextTests {
    private func model() -> ComparisonModel {
        ComparisonModel(environment: .init(
            loadSnapshot: { _ in throw StoreReadError.storeUnavailable },
            currentSnapshot: { nil },
            allSummaries: { [] },
            lastBoard: InMemoryLastBoard(),
            purposeText: { $0.map(\.rawValue) ?? "기본" },
            dateTimeText: { _ in "" }
        ))
    }

    private func movedRow(from location: [String], to after: [String]) -> ComparisonRow {
        let node = ConfigurationNode(id: fixedID(1), kind: .file, displayName: "spec.md", parentID: nil, sortIndex: 0)
        let change = NodeChange(
            nodeID: node.id, nodeKind: .file, kinds: [.moved],
            before: NodeState(displayName: "spec.md", location: location, parentID: fixedID(9), sortIndex: 0),
            after: NodeState(displayName: "spec.md", location: after, parentID: nil, sortIndex: 0)
        )
        return ComparisonRow(node: node, kinds: [.moved], change: change, children: [])
    }

    @Test("[W19-moved-label-parent] 이동 문구의 자리값은 이전 직접 부모 Wing 이름이고 최상위는 '최상위'다", arguments: [
        ([String](), "‘최상위’에서 이동"), (["문서"], "‘문서’에서 이동"), (["문서", "초안"], "‘초안’에서 이동"),
    ])
    func movedLabel(location: [String], expected: String) {
        let model = model()
        #expect(model.kindText(.moved, row: movedRow(from: location, to: [])) == expected)
    }

    @Test("[W19-change-details] '변경 내용' 위치는 Wing 경로를 ' › '로 잇고 최상위는 '최상위'다(0027)")
    func locationDetail() {
        let model = model()
        let row = movedRow(from: ["문서", "초안"], to: [])
        #expect(model.kindText(.moved, row: row) == "‘초안’에서 이동")
        // detailLines는 고른 행에서 계산하므로, 같은 규칙의 위치 문구를 직접 확인한다.
        #expect(ComparisonTextTests.location(model, row) == "문서 › 초안 → 최상위")
    }

    private static func location(_ model: ComparisonModel, _ row: ComparisonRow) -> String? {
        model.detailLines(for: row).first { $0.label == "위치" }?.text
    }
}
