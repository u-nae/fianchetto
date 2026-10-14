import Foundation

/// 복원 확인 시트가 보여 줄 내용(W20): 현재 구성에서 복원 결과로의 변화. 순서 변경도 늘 센다.
struct RestorePreview: Equatable, Sendable {
    /// 변경 목록의 한 행(DESIGN.md 16.3): 항목 기호 + 이름, 행 끝에 첫 변화의 기호 + 변화 문구, 둘째 줄부터 '이전 → 이후' 값.
    struct Row: Identifiable, Equatable, Sendable {
        var id: UUID
        /// 행이 가리키는 Node(제거 행은 현재 구성, 그 밖은 복원 결과). 트리 행과 같은 아이콘을 그리는 데 쓴다.
        var node: ConfigurationNode
        var name: String
        /// 첫 변화의 기호(19.3).
        var symbol: String
        /// 변화 종류 문구만 ' · '로 이은 것. 값은 valueTexts에 따로 둔다.
        var changeText: String
        /// 값이 있는 변화(이름·대상·URL·아이콘)의 '이전 → 이후', 19.3 순서.
        var valueTexts: [String]
        /// 이름과 변화 문구·값을 함께 읽는다(예: 'Dev, 제거됨').
        var accessibilityLabel: String
    }

    var revisionID: UUID
    var title: String
    var beforeText: String
    var afterText: String
    /// 현재 스냅샷 == 대상 스냅샷(서비스 판정과 같은 기준).
    var isIdentical: Bool
    var summaryText: String
    var boardNameText: String?
    var rows: [Row]
    var isSaving = false

    static func make(
        target: RevisionSummary, targetSnapshot: ConfigurationSnapshot, current: ConfigurationSnapshot,
        wording: ChangeWording, dateTimeText: (Date) -> String
    ) -> RestorePreview {
        let diff = ConfigurationDiffer.diff(current, targetSnapshot)
        let targetNodes = Dictionary(targetSnapshot.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentNodes = Dictionary(current.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = diff.changes.compactMap { change -> Row? in
            guard let node = targetNodes[change.nodeID] ?? currentNodes[change.nodeID] else { return nil }
            let kinds = ComparisonTree.ordered(change.kinds)
            let changeText = kinds.map { wording.kindText($0, change: change) }.joined(separator: " · ")
            let valueTexts = kinds.compactMap { wording.valueText($0, change: change) }
            let spokenText = kinds.map { kind -> String in
                let text = wording.kindText(kind, change: change)
                return wording.valueText(kind, change: change).map { "\(text) \($0)" } ?? text
            }.joined(separator: " · ")
            let name = (change.after ?? change.before)?.displayName ?? node.displayName
            return Row(
                id: change.nodeID, node: node, name: name, symbol: kinds.first.map(ChangeWording.kindSymbol) ?? "",
                changeText: changeText, valueTexts: valueTexts, accessibilityLabel: String(localized: "\(name), \(spokenText)")
            )
        }
        return RestorePreview(
            revisionID: target.id,
            title: String(localized: "#\(target.sequence) 구성으로 복원"),
            beforeText: String(localized: "현재 구성"),
            afterText: String(localized: "#\(target.sequence) · \(dateTimeText(target.recordedAt))"),
            isIdentical: current == targetSnapshot,
            summaryText: ChangeWording.summaryText(ComparisonTree.summary(diff, showsReorder: true)),
            boardNameText: diff.projectRename.map { ChangeWording.arrow($0.before, $0.after) },
            rows: rows
        )
    }
}
