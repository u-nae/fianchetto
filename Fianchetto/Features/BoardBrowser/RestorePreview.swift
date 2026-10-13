import Foundation

/// 복원 확인 시트가 보여 줄 내용(W20): 현재 구성에서 복원 결과로의 변화. 순서 변경도 늘 센다.
struct RestorePreview: Equatable, Sendable {
    struct Row: Identifiable, Equatable, Sendable {
        var id: UUID
        var name: String
        var symbol: String
        var changeText: String
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
        let rows = diff.changes.map { change -> Row in
            let kinds = ComparisonTree.ordered(change.kinds)
            let changeText = kinds.map { kind -> String in
                let text = wording.kindText(kind, change: change)
                return wording.valueText(kind, change: change).map { "\(text) \($0)" } ?? text
            }.joined(separator: " · ")
            let name = (change.after ?? change.before)?.displayName ?? ""
            return Row(
                id: change.nodeID, name: name, symbol: kinds.first.map(ChangeWording.kindSymbol) ?? "",
                changeText: changeText, accessibilityLabel: String(localized: "\(name), \(changeText)")
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
