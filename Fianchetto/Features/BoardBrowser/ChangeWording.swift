import Foundation

/// 변화 문구(DESIGN.md 19.3)와 '이전 → 이후' 값. 비교 화면(W19)과 복원 확인 시트(W20)가 함께 쓴다.
struct ChangeWording {
    var purposeText: (BishopPurpose?) -> String

    static func kindSymbol(_ kind: NodeChangeKind) -> String {
        switch kind {
        case .added: "plus.circle"
        case .removed: "minus.circle"
        case .renamed: "pencil"
        case .moved: "arrow.turn.down.right"
        case .reordered: "arrow.up.arrow.down"
        case .targetReplaced: "arrow.triangle.swap"
        case .urlChanged: "link"
        case .purposeChanged: "paintbrush.pointed"
        }
    }

    func kindText(_ kind: NodeChangeKind, change: NodeChange?) -> String {
        switch kind {
        case .added: String(localized: "추가됨")
        case .removed: String(localized: "제거됨")
        case .renamed: String(localized: "이름 변경")
        case .moved: String(localized: "‘\(change?.before?.location.last ?? String(localized: "최상위"))’에서 이동")
        case .reordered: String(localized: "순서 변경")
        case .targetReplaced: String(localized: "대상 교체")
        case .urlChanged: String(localized: "URL 변경")
        case .purposeChanged: String(localized: "아이콘 변경")
        }
    }

    /// 이름·대상·URL·아이콘 변화의 '이전 → 이후' 값. 그 밖의 종류는 nil.
    func valueText(_ kind: NodeChangeKind, change: NodeChange) -> String? {
        guard let before = change.before, let after = change.after else { return nil }
        switch kind {
        case .renamed: return Self.arrow(before.displayName, after.displayName)
        case .targetReplaced: return Self.arrow(before.recordedPath ?? "", after.recordedPath ?? "")
        case .urlChanged: return Self.arrow(before.url ?? "", after.url ?? "")
        case .purposeChanged: return Self.arrow(purposeName(before.purpose), purposeName(after.purpose))
        case .added, .removed, .moved, .reordered: return nil
        }
    }

    static func arrow(_ before: String, _ after: String) -> String {
        String(localized: "\(before) → \(after)")
    }

    /// '변화 N개 · Board 이름 변경 · 순서 변경 N개 숨김'(0027).
    static func summaryText(_ summary: ComparisonSummary) -> String {
        var parts: [String] = []
        if summary.changedCount > 0 || !summary.boardRenamed {
            parts.append(String(localized: "변화 \(summary.changedCount)개"))
        }
        if summary.boardRenamed { parts.append(String(localized: "Board 이름 변경")) }
        if summary.hiddenReorderCount > 0 { parts.append(String(localized: "순서 변경 \(summary.hiddenReorderCount)개 숨김")) }
        return parts.joined(separator: " · ")
    }

    private func purposeName(_ key: String?) -> String {
        purposeText(key.flatMap(BishopPurpose.init(rawValue:)))
    }
}
