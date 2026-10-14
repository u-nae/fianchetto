import Foundation
import Observation

/// 비교할 구성 하나: 현재 구성 또는 revision 하나.
enum ComparisonTarget: Hashable, Sendable {
    case current
    case revision(UUID)
}

/// 구성 비교 화면의 상태(W19, DESIGN.md 19장, 0024·0027).
/// 저장된 구성만 쓰고 고른 두 구성만 디코딩한다. 파일 시스템에 접근하지 않고 revision을 만들지 않는다.
@MainActor
@Observable
final class ComparisonModel {
    struct Environment {
        /// revision 구성 하나를 읽는다(고른 대상만).
        var loadSnapshot: (UUID) async throws -> ConfigurationSnapshot
        /// 지금 현재 구성(이미 읽은 값).
        var currentSnapshot: () -> ConfigurationSnapshot?
        /// 대상 메뉴에 보일 모든 revision 목록 정보(순번 역순). 스냅샷은 디코딩하지 않는다.
        var allSummaries: () async throws -> [RevisionSummary]
        var lastBoard: any LastBoardRecord
        var purposeText: (BishopPurpose?) -> String
        var dateTimeText: (Date) -> String
    }

    /// 비교에서 고른 행. 'Board 이름' 행은 Node가 아니다.
    enum Selection: Hashable {
        case row(UUID)
        case boardName
    }

    /// 보기 방식(19.2): 통합 트리(기본) 또는 나란히 두 트리.
    enum Style: String, Hashable, Sendable {
        case unified
        case sideBySide
    }

    /// '변경 내용'의 한 줄.
    struct DetailLine: Equatable {
        var label: String
        var text: String
    }

    private(set) var isOpen = false
    private(set) var before: ComparisonTarget?
    private(set) var after: ComparisonTarget?
    private(set) var beforeSnapshot: ConfigurationSnapshot?
    private(set) var afterSnapshot: ConfigurationSnapshot?
    private(set) var diff: ConfigurationDiff?
    private(set) var rows: [ComparisonRow] = []
    /// 나란히 보기의 두 열(19.5). 각 열은 그 구성의 트리 구조를 따른다.
    private(set) var beforeRows: [ComparisonRow] = []
    private(set) var afterRows: [ComparisonRow] = []
    private(set) var targetChoices: [RevisionSummary] = []
    private(set) var unreadableNotice = false
    /// 고른 행. 나란히 보기에서는 두 열이 같은 선택을 함께 강조한다. 직접 바꾸면(통합 트리) 고른 열은 지운다.
    var selection: Selection? {
        didSet { selectedSide = nil }
    }
    /// 나란히 보기에서 행을 고른 열. 열기·Finder에서 보기는 그 열 구성의 항목으로 한다(19.6).
    private(set) var selectedSide: ComparisonTree.Side?
    /// 보기 방식. 마지막 선택을 기억하고 기본은 통합이다.
    var style: Style {
        didSet { environment.lastBoard.comparisonStyle = style.rawValue }
    }
    /// '바뀐 항목만 보기'. 비교를 열 때마다 끈다. 바꾸면 변화가 있는 행의 조상 Wing을 다시 펼친다.
    var changedOnly = false {
        didSet { expandToChanges() }
    }
    /// '순서 변경 표시'. 기본은 켬이고 다시 실행해도 기억한다.
    var showsReorder: Bool {
        didSet {
            environment.lastBoard.comparisonHidesReorder = !showsReorder
            expandToChanges()
        }
    }
    /// 펼친 Wing 행. 비교를 열거나 대상·거르기를 바꿀 때 변화가 있는 행의 조상을 펼친다.
    /// 그 뒤 사용자가 접은 것은 그대로 둔다(DESIGN 19.4·19.5).
    var expandedRowIDs: Set<UUID> = []

    private var generation = 0
    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
        showsReorder = !environment.lastBoard.comparisonHidesReorder
        style = environment.lastBoard.comparisonStyle.flatMap(Style.init(rawValue:)) ?? .unified
    }

    // MARK: 열기·대상 바꾸기·닫기

    /// 두 대상을 읽어 비교를 연다. 읽지 못하면 안내만 하고 열지 않는다(false). 늦게 끝난 요청은 버린다.
    @discardableResult
    func open(before: ComparisonTarget, after: ComparisonTarget) async -> Bool {
        generation += 1
        let request = generation
        guard let loaded = await load(before, after), request == generation else {
            if request == generation { unreadableNotice = true }
            return false
        }
        // 대상 메뉴 목록(목록 정보만). 읽지 못해도 비교는 연다.
        let summaries = (try? await environment.allSummaries()) ?? []
        guard request == generation else { return false }
        targetChoices = summaries
        remember(summaries)
        apply(before: before, after: after, loaded: loaded)
        // '바뀐 항목만 보기'는 닫을 때 끄므로 열 때마다 꺼진 상태로 시작한다.
        isOpen = true
        select(nil)
        return true
    }

    /// 대상 메뉴에서 바꾼다. 읽기가 성공할 때까지 지금 대상과 결과를 그대로 둔다.
    func setBefore(_ target: ComparisonTarget) async {
        guard isOpen, let after else { return }
        await change(before: target, after: after)
    }

    func setAfter(_ target: ComparisonTarget) async {
        guard isOpen, let before else { return }
        await change(before: before, after: target)
    }

    func close() {
        generation += 1
        isOpen = false
        before = nil
        after = nil
        beforeSnapshot = nil
        afterSnapshot = nil
        diff = nil
        rows = []
        beforeRows = []
        afterRows = []
        selection = nil
        selectedSide = nil
        changedOnly = false
        expandedRowIDs = []
    }

    func dismissNotice() {
        unreadableNotice = false
    }

    // MARK: 표시 값

    var isSameTarget: Bool { isOpen && before == after }

    /// 다른 대상인데 차이가 하나도 없다(Board 이름 포함).
    var hasNoChange: Bool { isOpen && !isSameTarget && diff?.isEmpty == true }

    var shownRows: [ComparisonRow] {
        ComparisonTree.filter(rows, showsReorder: showsReorder, changedOnly: changedOnly)
    }

    /// 나란히 보기의 한 열(거르기 적용).
    func shownRows(_ side: ComparisonTree.Side) -> [ComparisonRow] {
        ComparisonTree.filter(side == .before ? beforeRows : afterRows, showsReorder: showsReorder, changedOnly: changedOnly)
    }

    /// 나란히 보기의 열 머리: 그 열의 대상 이름.
    func columnTitle(_ side: ComparisonTree.Side) -> String {
        (side == .before ? before : after).map(targetText) ?? ""
    }

    /// 나란히 보기 'Board 이름' 행에 보일 그 열 구성의 Board 이름.
    func boardName(_ side: ComparisonTree.Side) -> String {
        (side == .before ? beforeSnapshot : afterSnapshot)?.projectName ?? ""
    }

    /// 나란히 보기 'Board 이름' 행의 VoiceOver 라벨: 'Board 이름, <이름>, 이름 변경'.
    func boardNameAccessibilityLabel(_ side: ComparisonTree.Side) -> String {
        [String(localized: "Board 이름"), boardName(side), String(localized: "이름 변경")].joined(separator: ", ")
    }

    /// 그 열에 이 항목이 있는지(한쪽에만 있는 항목은 반대쪽에 행이 없다).
    func contains(_ id: UUID, in side: ComparisonTree.Side) -> Bool {
        Self.search(side == .before ? beforeRows : afterRows, id) != nil
    }

    /// 행을 고른다. 나란히 보기에서는 고른 열을 기억하고, 두 열 모두에서 그 항목의 조상 Wing을 펼친다(19.5).
    func select(_ selection: Selection?, in side: ComparisonTree.Side? = nil) {
        self.selection = selection
        selectedSide = side
        guard case let .row(id) = selection, side != nil else { return }
        for rows in [beforeRows, afterRows] {
            expandedRowIDs.formUnion(Self.ancestors(of: id, in: rows) ?? [])
        }
    }

    /// 순서 숨김과 '바뀐 항목만 보기'로 보일 행이 하나도 없다('표시할 변화 없음').
    var isFilteredEmpty: Bool { isOpen && !isSameTarget && !hasNoChange && shownRows.isEmpty && !showsBoardNameRow }

    var showsBoardNameRow: Bool { diff?.projectRename != nil }

    var summary: ComparisonSummary? {
        diff.map { ComparisonTree.summary($0, showsReorder: showsReorder) }
    }

    /// '변화 N개 · Board 이름 변경 · 순서 변경 N개 숨김'(0027). 같은 대상이면 셀 것이 없어 비운다.
    var summaryText: String {
        guard let summary, !isSameTarget else { return "" }
        return ChangeWording.summaryText(summary)
    }

    func targetText(_ target: ComparisonTarget) -> String {
        switch target {
        case .current: return String(localized: "현재 구성")
        case let .revision(id):
            guard let summary = targetChoices.first(where: { $0.id == id }) ?? knownSummaries[id] else { return "#?" }
            return String(localized: "#\(summary.sequence) · \(environment.dateTimeText(summary.recordedAt))")
        }
    }

    /// 대상 메뉴의 revision 목록 문구.
    func choiceText(_ summary: RevisionSummary) -> String {
        String(localized: "#\(summary.sequence) · \(environment.dateTimeText(summary.recordedAt))")
    }

    /// 행 끝의 변화 문구(19.3 표 순서, ' · '로 잇는다). 보이지 않는 종류(순서 숨김)는 뺀다.
    func changeText(_ row: ComparisonRow) -> String {
        visibleKinds(row).map { kindText($0, row: row) }.joined(separator: " · ")
    }

    /// 나란히 보기의 짧은 변화 문구(19.5).
    func shortChangeText(_ row: ComparisonRow) -> String {
        visibleKinds(row).map(shortKindText).joined(separator: " · ")
    }

    func shortKindText(_ kind: NodeChangeKind) -> String {
        switch kind {
        case .added: String(localized: "추가")
        case .removed: String(localized: "제거")
        case .renamed: String(localized: "이름")
        case .moved: String(localized: "이동")
        case .reordered: String(localized: "순서")
        case .targetReplaced: String(localized: "대상")
        case .urlChanged: String(localized: "URL")
        case .purposeChanged: String(localized: "아이콘")
        }
    }

    func visibleKinds(_ row: ComparisonRow) -> [NodeChangeKind] {
        showsReorder ? row.kinds : row.kinds.filter { $0 != .reordered }
    }

    func kindText(_ kind: NodeChangeKind, row: ComparisonRow) -> String {
        wording.kindText(kind, change: row.change)
    }

    static func kindSymbol(_ kind: NodeChangeKind) -> String {
        ChangeWording.kindSymbol(kind)
    }

    func findRow(_ id: UUID) -> ComparisonRow? {
        Self.search(rows, id)
    }

    private static func search(_ rows: [ComparisonRow], _ id: UUID) -> ComparisonRow? {
        for row in rows {
            if row.id == id { return row }
            if let found = search(row.children, id) { return found }
        }
        return nil
    }

    /// 그 항목의 조상 행 ID(위에서 아래로). 없으면 nil.
    private static func ancestors(of id: UUID, in rows: [ComparisonRow]) -> [UUID]? {
        for row in rows {
            if row.id == id { return [] }
            if let found = ancestors(of: id, in: row.children) { return [row.id] + found }
        }
        return nil
    }

    /// 인스펙터 '변경 내용' 자리의 상태: 고른 것 없음, 고른 행에 바뀐 내용 없음, 바뀐 내용 있음.
    enum DetailState: Equatable {
        case noSelection
        case unchanged
        case changed
    }

    var detailState: DetailState {
        guard selection != nil else { return .noSelection }
        return detailLines.isEmpty ? .unchanged : .changed
    }

    var selectedRow: ComparisonRow? {
        guard case let .row(id) = selection else { return nil }
        return findRow(id)
    }

    /// 열기·Finder에서 보기에 쓸 항목: 나란히 보기에서는 고른 열 구성의 항목, 통합 트리에서는 그 행의 항목(제거 행은 이전 구성).
    var selectedNode: ConfigurationNode? {
        guard case let .row(id) = selection else { return nil }
        if style == .sideBySide, let side = selectedSide {
            return Self.search(side == .before ? beforeRows : afterRows, id)?.node
        }
        return selectedRow?.node
    }

    /// 고른 행의 '변경 내용'(19.4): 바뀐 값만 '이전 → 이후'. 추가·제거는 한쪽 값만.
    var detailLines: [DetailLine] {
        switch selection {
        case .boardName:
            guard let rename = diff?.projectRename else { return [] }
            return [DetailLine(label: String(localized: "이름"), text: ChangeWording.arrow(rename.before, rename.after))]
        case .row:
            return selectedRow.map(detailLines(for:)) ?? []
        case nil:
            return []
        }
    }

    func detailLines(for row: ComparisonRow) -> [DetailLine] {
        row.change.map { lines(for: $0, kind: row.node.kind) } ?? []
    }

    // MARK: 내부

    /// 진입 명령 등에서 대상 문구에 쓰는 목록 정보(대상 메뉴 목록을 읽기 전에도 쓸 수 있게).
    private var knownSummaries: [UUID: RevisionSummary] = [:]

    func remember(_ summaries: [RevisionSummary]) {
        for summary in summaries { knownSummaries[summary.id] = summary }
    }

    private func change(before: ComparisonTarget, after: ComparisonTarget) async {
        generation += 1
        let request = generation
        guard let loaded = await load(before, after), request == generation, isOpen else {
            if request == generation, isOpen { unreadableNotice = true }
            return
        }
        apply(before: before, after: after, loaded: loaded)
        select(nil)
    }

    private func apply(before: ComparisonTarget, after: ComparisonTarget, loaded: (ConfigurationSnapshot, ConfigurationSnapshot)) {
        self.before = before
        self.after = after
        beforeSnapshot = loaded.0
        afterSnapshot = loaded.1
        let diff = ConfigurationDiffer.diff(loaded.0, loaded.1)
        self.diff = diff
        rows = ComparisonTree.build(before: loaded.0, after: loaded.1, diff: diff)
        beforeRows = ComparisonTree.sideRows(.before, before: loaded.0, after: loaded.1, diff: diff)
        afterRows = ComparisonTree.sideRows(.after, before: loaded.0, after: loaded.1, diff: diff)
        expandToChanges()
    }

    /// 보이는 변화가 있는 행의 조상 Wing을 모두 펼친다(통합 트리와 나란히 보기의 두 열).
    private func expandToChanges() {
        var result: Set<UUID> = []
        func walk(_ rows: [ComparisonRow], ancestors: [UUID]) -> Void {
            for row in rows {
                if !visibleKinds(row).isEmpty { result.formUnion(ancestors) }
                walk(row.children, ancestors: ancestors + [row.id])
            }
        }
        for tree in [rows, beforeRows, afterRows] { walk(tree, ancestors: []) }
        expandedRowIDs = result
    }

    private func load(_ before: ComparisonTarget, _ after: ComparisonTarget) async -> (ConfigurationSnapshot, ConfigurationSnapshot)? {
        guard let first = await snapshot(before), let second = await snapshot(after) else { return nil }
        return (first, second)
    }

    private func snapshot(_ target: ComparisonTarget) async -> ConfigurationSnapshot? {
        switch target {
        case .current: return environment.currentSnapshot()
        case let .revision(id): return try? await environment.loadSnapshot(id)
        }
    }

    private var wording: ChangeWording { ChangeWording(purposeText: environment.purposeText) }

    private func locationText(_ state: NodeState) -> String {
        state.location.isEmpty ? String(localized: "최상위") : state.location.joined(separator: " › ")
    }

    private func lines(for change: NodeChange, kind: NodeKind) -> [DetailLine] {
        let name = String(localized: "이름"), place = String(localized: "위치"), target = String(localized: "대상")
        let url = String(localized: "URL"), icon = String(localized: "아이콘")
        let isLinked = kind == .file || kind == .folder
        if change.kinds.contains(.added), let after = change.after {
            return [DetailLine(label: "", text: String(localized: "추가됨")), DetailLine(label: place, text: locationText(after))]
                + (isLinked ? [DetailLine(label: target, text: after.recordedPath ?? "")] : [])
                + (kind == .webLink ? [DetailLine(label: url, text: after.url ?? "")] : [])
        }
        if change.kinds.contains(.removed), let before = change.before {
            return [DetailLine(label: "", text: String(localized: "제거됨")), DetailLine(label: place, text: locationText(before))]
                + (isLinked ? [DetailLine(label: target, text: before.recordedPath ?? "")] : [])
                + (kind == .webLink ? [DetailLine(label: url, text: before.url ?? "")] : [])
        }
        guard let before = change.before, let after = change.after else { return [] }
        var result: [DetailLine] = []
        if change.kinds.contains(.renamed), let text = wording.valueText(.renamed, change: change) { result.append(DetailLine(label: name, text: text)) }
        if change.kinds.contains(.moved) { result.append(DetailLine(label: place, text: ChangeWording.arrow(locationText(before), locationText(after)))) }
        if change.kinds.contains(.reordered) { result.append(DetailLine(label: "", text: String(localized: "순서 변경"))) }
        if change.kinds.contains(.targetReplaced), let text = wording.valueText(.targetReplaced, change: change) {
            result.append(DetailLine(label: target, text: text))
        }
        if change.kinds.contains(.urlChanged), let text = wording.valueText(.urlChanged, change: change) {
            result.append(DetailLine(label: url, text: text))
        }
        if change.kinds.contains(.purposeChanged), let text = wording.valueText(.purposeChanged, change: change) {
            result.append(DetailLine(label: icon, text: text))
        }
        return result
    }
}
