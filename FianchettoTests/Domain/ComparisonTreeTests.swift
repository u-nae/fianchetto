import Foundation
import Testing
@testable import Fianchetto

/// 통합 트리(W19, DESIGN.md 19.4)와 결정 removed_row_placement.
@Suite("비교 통합 트리(W19)")
struct ComparisonTreeTests {
    static let dev = fixedID(301), backend = fixedID(302), notes = fixedID(303)
    static let docs = fixedID(304), spec = fixedID(305), api = fixedID(306)
    static let design = fixedID(307), wiki = fixedID(308), draft = fixedID(309)

    /// 순번 3 구성: 개발[backend, notes.md], 문서[spec.md], API 명세.
    static func base() -> ConfigurationSnapshot {
        ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.group(dev, "개발", order: 0),
            SnapshotFixtures.folder(backend, "backend", parent: dev, order: 0, reference: fixedID(402), path: "/dev/legacy-api"),
            SnapshotFixtures.file(notes, "notes.md", parent: dev, order: 1, reference: fixedID(403), path: "/dev/notes.md"),
            SnapshotFixtures.group(docs, "문서", order: 1),
            SnapshotFixtures.file(spec, "spec.md", parent: docs, order: 0, reference: fixedID(405), path: "/docs/spec.md"),
            SnapshotFixtures.webLink(api, "API 명세", order: 2, url: "https://old.example.com"),
        ])
    }

    static func removing(_ ids: Set<UUID>, from snapshot: ConfigurationSnapshot) -> ConfigurationSnapshot {
        var copy = snapshot
        copy.nodes.removeAll { ids.contains($0.id) }
        return copy
    }

    /// 행 트리를 "이름" 또는 "이름(제거됨)"과 들여쓰기 경로로 펼친다.
    static func outline(_ rows: [ComparisonRow], prefix: String = "") -> [String] {
        rows.flatMap { row in
            ["\(prefix)\(row.node.displayName)\(row.isRemoved ? "(제거됨)" : "")"] + outline(row.children, prefix: prefix + row.node.displayName + "/")
        }
    }

    static func tree(_ before: ConfigurationSnapshot, _ after: ConfigurationSnapshot) -> [ComparisonRow] {
        ComparisonTree.build(before: before, after: after, diff: ConfigurationDiffer.diff(before, after))
    }

    @Test("[W19-removed-placement-rule] 결정 removed_row_placement는 여섯 조합에 규칙 하나씩 대응한다", arguments: [
        (RemovedRowPlacement.ParentState.topLevel, true, RemovedRowPlacement.Parent.root, RemovedRowPlacement.Position.afterPrecedingSibling),
        (.topLevel, false, .root, .first),
        (.kept, true, .keptParentRow, .afterPrecedingSibling),
        (.kept, false, .keptParentRow, .first),
        (.removed, true, .removedParentRow, .afterPrecedingSibling),
        (.removed, false, .removedParentRow, .first),
    ])
    func decision(state: RemovedRowPlacement.ParentState, preceding: Bool, parent: RemovedRowPlacement.Parent, position: RemovedRowPlacement.Position) {
        let result = RemovedRowPlacement.decide(parent: state, hasPrecedingSibling: preceding)
        #expect(result.parent == parent)
        #expect(result.position == position)
    }

    @Test("[W19-merged-tree] 이후 구성 트리에 변화를 붙이고 제거 항목을 이전 위치에 끼워 넣는다", .tags(.A07))
    func mergedTree() {
        var after = Self.removing([Self.notes], from: Self.base())
        after.nodes.append(SnapshotFixtures.webLink(Self.wiki, "위키", order: 1, url: "https://wiki"))
        after = after.updating(Self.docs) { $0.sortIndex = 2 }.updating(Self.api) { $0.sortIndex = 3 }
        let rows = Self.tree(Self.base(), after)
        #expect(Self.outline(rows) == ["개발", "개발/backend", "개발/notes.md(제거됨)", "위키", "문서", "문서/spec.md", "API 명세"])
        #expect(rows.first { $0.id == Self.wiki }?.kinds == [.added])
        #expect(rows.first { $0.id == Self.dev }?.kinds == [])
    }

    enum Placement: String, CaseIterable, Sendable {
        case topLevelAfterSibling, firstInKeptParent, underMovedParent, skipMovedSibling, removedWingNests, bothRemoved, sameAnchorKeepsOrder, skipMovedToEarlierSibling
    }

    @Test("[W19-removed-placement-examples] 제거 항목을 끼워 넣는 위치는 결정 removed_row_placement를 따른다", arguments: Placement.allCases)
    func placement(example: Placement) {
        let base = Self.base()
        let result: [String]
        switch example {
        case .topLevelAfterSibling:
            result = Self.outline(Self.tree(base, Self.removing([Self.api], from: base)))
            #expect(result == ["개발", "개발/backend", "개발/notes.md", "문서", "문서/spec.md", "API 명세(제거됨)"])
        case .firstInKeptParent:
            result = Self.outline(Self.tree(base, Self.removing([Self.backend], from: base)))
            #expect(Array(result.prefix(3)) == ["개발", "개발/backend(제거됨)", "개발/notes.md"])
        case .underMovedParent:
            let after = Self.removing([Self.notes], from: base).updating(Self.dev) { $0.parentID = Self.docs; $0.sortIndex = 1 }
            result = Self.outline(Self.tree(base, after))
            #expect(result == ["문서", "문서/spec.md", "문서/개발", "문서/개발/backend", "문서/개발/notes.md(제거됨)", "API 명세"])
        case .skipMovedSibling:
            let after = Self.removing([Self.notes], from: base).updating(Self.backend) { $0.parentID = Self.docs; $0.sortIndex = 1 }
            result = Self.outline(Self.tree(base, after))
            #expect(Array(result.prefix(2)) == ["개발", "개발/notes.md(제거됨)"])
        case .removedWingNests:
            result = Self.outline(Self.tree(base, Self.removing([Self.dev, Self.backend, Self.notes], from: base)))
            #expect(result == ["개발(제거됨)", "개발/backend(제거됨)", "개발/notes.md(제거됨)", "문서", "문서/spec.md", "API 명세"])
        case .bothRemoved:
            result = Self.outline(Self.tree(base, Self.removing([Self.backend, Self.notes], from: base)))
            #expect(Array(result.prefix(3)) == ["개발", "개발/backend(제거됨)", "개발/notes.md(제거됨)"])
        case .skipMovedToEarlierSibling:
            // 이전: 개발[backend, notes.md, design.md]. notes.md는 문서로 옮기고 design.md는 제거 → design.md는 backend 뒤.
            var before = base
            before.nodes.append(SnapshotFixtures.file(Self.design, "design.md", parent: Self.dev, order: 2, reference: fixedID(407), path: "/dev/design.md"))
            let after = Self.removing([Self.design], from: before).updating(Self.notes) { $0.parentID = Self.docs; $0.sortIndex = 1 }
            result = Self.outline(Self.tree(before, after))
            #expect(Array(result.prefix(3)) == ["개발", "개발/backend", "개발/design.md(제거됨)"])
        case .sameAnchorKeepsOrder:
            result = Self.outline(Self.tree(base, Self.removing([Self.docs, Self.spec, Self.api], from: base)))
            #expect(result == ["개발", "개발/backend", "개발/notes.md", "문서(제거됨)", "문서/spec.md(제거됨)", "API 명세(제거됨)"])
        }
    }

    @Test("[W19-multiple-kinds] [W19-kinds-order] 한 행의 여러 변화는 19.3 표 순서다", .tags(.A07))
    func kindsOrder() {
        let after = Self.base().updating(Self.backend) {
            $0.displayName = "api"; $0.purpose = "code"; $0.referenceID = fixedID(499); $0.parentID = Self.docs; $0.sortIndex = 1
        }
        let row = Self.tree(Self.base(), after).first { $0.id == Self.docs }?.children.first { $0.id == Self.backend }
        #expect(row?.kinds == [.renamed, .moved, .targetReplaced, .purposeChanged])
        #expect(ComparisonTree.ordered(Set(NodeChangeKind.allCases)) == ComparisonTree.kindOrder)
    }

    @Test("[W19-minimal-reorder-on-screen] 인덱스만 밀린 형제와 옮긴 Wing의 자손에는 변화가 붙지 않는다", .tags(.A07))
    func minimalReorder() {
        var after = Self.base().updating(Self.dev) { $0.parentID = Self.docs; $0.sortIndex = 1 }
            .updating(Self.backend) { $0.sortIndex = 1 }.updating(Self.notes) { $0.sortIndex = 2 }
        after.nodes.append(SnapshotFixtures.file(Self.design, "design.md", parent: Self.dev, order: 0, reference: fixedID(407), path: "/dev/design.md"))
        let diff = ConfigurationDiffer.diff(Self.base(), after)
        let rows = ComparisonTree.build(before: Self.base(), after: after, diff: diff)
        func changed(_ rows: [ComparisonRow]) -> [String] {
            rows.flatMap { ($0.kinds.isEmpty ? [] : [$0.node.displayName]) + changed($0.children) }
        }
        #expect(Set(changed(rows)) == ["design.md", "개발"])
        #expect(ComparisonTree.summary(diff, showsReorder: true).changedCount == 2)
    }

    @Test("[W19-reorder-toggle] '순서 변경 표시'를 끄면 순서만 바뀐 행의 표시와 요약 수에서 빼고 숨김 수를 센다")
    func reorderToggle() {
        let after = Self.base()
            .updating(Self.api) { $0.sortIndex = 1 }.updating(Self.docs) { $0.sortIndex = 2 }
            .updating(Self.notes) { $0.sortIndex = 0; $0.displayName = "todo.md" }.updating(Self.backend) { $0.sortIndex = 1 }
        let diff = ConfigurationDiffer.diff(Self.base(), after)
        let rows = ComparisonTree.build(before: Self.base(), after: after, diff: diff)
        let shown = ComparisonTree.filter(rows, showsReorder: true, changedOnly: false)
        let hidden = ComparisonTree.filter(rows, showsReorder: false, changedOnly: false)
        func kinds(_ rows: [ComparisonRow], _ id: UUID) -> [NodeChangeKind]? {
            for row in rows {
                if row.id == id { return row.kinds }
                if let found = kinds(row.children, id) { return found }
            }
            return nil
        }
        #expect(kinds(shown, Self.api) == [.reordered])
        #expect(kinds(shown, Self.notes) == [.renamed, .reordered])
        #expect(kinds(shown, Self.backend) == [])
        #expect(kinds(hidden, Self.api) == [])
        #expect(kinds(hidden, Self.notes) == [.renamed])
        #expect(ComparisonTree.summary(diff, showsReorder: true) == .init(changedCount: 2, hiddenReorderCount: 0, boardRenamed: false))
        #expect(ComparisonTree.summary(diff, showsReorder: false) == .init(changedCount: 1, hiddenReorderCount: 1, boardRenamed: false))
    }

    @Test("[W19-summary-count] 요약 수는 제거된 Wing의 자손도 각각 세고 Board 이름 변경은 따로 둔다")
    func summaryCount() {
        var after = Self.removing([Self.dev, Self.backend, Self.notes], from: Self.base())
        after.projectName = "서비스 Alpha"
        let summary = ComparisonTree.summary(ConfigurationDiffer.diff(Self.base(), after), showsReorder: true)
        #expect(summary == .init(changedCount: 3, hiddenReorderCount: 0, boardRenamed: true))
    }

    @Test("[W19-changed-only-filter] '바뀐 항목만 보기'는 변화가 있는 행과 그 조상만 남긴다")
    func changedOnly() {
        let after = Self.base().updating(Self.spec) { $0.displayName = "spec-v2.md" }
        let rows = ComparisonTree.filter(Self.tree(Self.base(), after), showsReorder: true, changedOnly: true)
        #expect(Self.outline(rows) == ["문서", "문서/spec-v2.md"])
        #expect(rows.first?.kinds == [])
        #expect(Self.outline(ComparisonTree.filter(Self.tree(Self.base(), after), showsReorder: true, changedOnly: false)).count == 6)
    }

    @Test("[W19-reorder-hidden-zero] 순서 숨김과 '바뀐 항목만 보기'로 남는 행이 없으면 빈 목록이다")
    func filteredEmpty() {
        let after = Self.base().updating(Self.api) { $0.sortIndex = 1 }.updating(Self.docs) { $0.sortIndex = 2 }
        let rows = Self.tree(Self.base(), after)
        #expect(ComparisonTree.filter(rows, showsReorder: false, changedOnly: true).isEmpty)
        #expect(ComparisonTree.filter(rows, showsReorder: false, changedOnly: false).count == 3)
    }
}
