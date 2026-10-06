import SwiftUI

/// 구성 비교 화면(W19, DESIGN.md 19장): 비교 띠와 통합 트리 또는 나란히 두 트리. 표시 전용이며 열기·Finder에서 보기만 한다.
struct ComparisonView: View {
    let model: BoardBrowserModel

    private var comparison: ComparisonModel { model.comparison }

    var body: some View {
        let notice = comparison.unreadableNotice
        VStack(spacing: 0) {
            ComparisonBar(model: model)
            content
        }
        // Esc로 비교를 닫는다. 시트·입력 칸이 열려 있으면 그쪽이 먼저 받는다(0027).
        .onExitCommand { model.closeComparison() }
        .alert(
            String(localized: "이 기록을 읽을 수 없습니다"),
            isPresented: Binding(get: { notice }, set: { if !$0 { comparison.dismissNotice() } })
        ) {
            Button("확인", role: .cancel) { comparison.dismissNotice() }
        }
    }

    @ViewBuilder
    private var content: some View {
        // 빈 상태는 남은 높이를 채워 비교 띠가 위에 붙어 있게 한다.
        if comparison.isSameTarget {
            ContentUnavailableView("같은 구성입니다", systemImage: "equal.circle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if comparison.hasNoChange {
            ContentUnavailableView("변화 없음", systemImage: "equal.circle", description: Text("두 구성이 같습니다."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if comparison.isFilteredEmpty {
            ContentUnavailableView(
                "표시할 변화 없음", systemImage: "line.3.horizontal.decrease.circle",
                description: Text("순서 변경 표시를 켜면 순서만 바뀐 항목이 보입니다.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if comparison.style == .sideBySide {
            // 19.5: 왼쪽 이전, 오른쪽 이후. VoiceOver는 왼쪽 열을 다 읽은 뒤 오른쪽 열을 읽는다.
            HStack(spacing: 0) {
                ComparisonColumn(model: model, side: .before)
                Divider()
                ComparisonColumn(model: model, side: .after)
            }
        } else {
            let selection = comparison.selection
            ComparisonList(model: model, side: nil, rows: comparison.shownRows, selection: selection)
                .accessibilityIdentifier("compare-tree")
        }
    }
}

/// 비교 트리 목록 하나: 통합 트리(side 없음) 또는 나란히 보기의 한 열. 오른쪽 클릭·이중 클릭은 열기·Finder에서 보기만 둔다(19.6).
private struct ComparisonList: View {
    let model: BoardBrowserModel
    let side: ComparisonTree.Side?
    let rows: [ComparisonRow]
    let selection: ComparisonModel.Selection?

    private var comparison: ComparisonModel { model.comparison }

    var body: some View {
        List(selection: Binding(get: { selection }, set: { comparison.select($0, in: side) })) {
            if comparison.showsBoardNameRow {
                BoardNameRow(model: model, side: side)
                    .tag(ComparisonModel.Selection.boardName)
            }
            ForEach(rows) { row in
                ComparisonBranch(model: model, row: row, side: side)
            }
        }
        .contextMenu(forSelectionType: ComparisonModel.Selection.self) { selection in
            if selection.count == 1, case let .row(id)? = selection.first, let row = comparison.findRow(id) {
                if row.node.kind != .group {
                    Button("열기") { run(id) { await model.openSelected() } }
                }
                if row.node.kind == .file || row.node.kind == .folder {
                    Button("Finder에서 보기") { run(id) { await model.revealSelected() } }
                }
            }
        } primaryAction: { selection in
            if selection.count == 1, case let .row(id)? = selection.first {
                run(id) { await model.openSelected() }
            }
        }
    }

    private func run(_ id: UUID, _ action: @escaping @MainActor () async -> Void) {
        comparison.select(.row(id), in: side)
        Task { await action() }
    }
}

/// 나란히 보기의 한 열(19.5): 열 머리(대상 이름)와 트리. 고른 항목이 이 열에 있으면 그 행으로 스크롤한다.
/// 스크롤을 늘 붙여 움직이는 동기화는 하지 않는다.
private struct ComparisonColumn: View {
    let model: BoardBrowserModel
    let side: ComparisonTree.Side

    var body: some View {
        let comparison = model.comparison
        let selection = comparison.selection
        VStack(alignment: .leading, spacing: 0) {
            Text(comparison.columnTitle(side))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(side == .before ? "compare-before-title" : "compare-after-title")
            ScrollViewReader { proxy in
                ComparisonList(model: model, side: side, rows: comparison.shownRows(side), selection: selection)
                    .onChange(of: selection) { _, next in
                        guard case let .row(id)? = next, comparison.contains(id, in: side) else { return }
                        // 조상을 펼친 결과가 목록에 반영된 다음에 스크롤한다.
                        Task { proxy.scrollTo(id) }
                    }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(side == .before ? String(localized: "이전 구성") : String(localized: "이후 구성"))
        .accessibilityIdentifier(side == .before ? "compare-before-tree" : "compare-after-tree")
    }
}

/// 비교 트리의 가지. 펼침은 모델이 가진다(변화가 있는 행의 조상을 처음에 펼친다). 나란히 보기의 두 열도 같은 펼침을 쓴다.
private struct ComparisonBranch: View {
    let model: BoardBrowserModel
    let row: ComparisonRow
    let side: ComparisonTree.Side?

    var body: some View {
        if row.children.isEmpty {
            item
        } else {
            // Observation은 body에서 읽은 값만 추적하므로 Binding 클로저 밖에서 먼저 읽는다.
            let expanded = model.comparison.expandedRowIDs.contains(row.id)
            DisclosureGroup(isExpanded: Binding(get: { expanded }, set: { open in
                if open { model.comparison.expandedRowIDs.insert(row.id) } else { model.comparison.expandedRowIDs.remove(row.id) }
            })) {
                ForEach(row.children) { child in
                    ComparisonBranch(model: model, row: child, side: side)
                }
            } label: {
                item
            }
        }
    }

    private var item: some View {
        ComparisonRowView(model: model, row: row, short: side != nil)
            .tag(ComparisonModel.Selection.row(row.id))
    }
}

/// 비교 띠(19.2): 첫 줄 기호 + '구성 비교'와 거르기·닫기, 둘째 줄 이전 → 이후 대상 메뉴와 요약.
private struct ComparisonBar: View {
    let model: BoardBrowserModel

    var body: some View {
        let comparison = model.comparison
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Label("구성 비교", systemImage: "arrow.left.arrow.right")
                    .font(.callout.bold())
                Spacer()
                Picker("보기 방식", selection: Binding(get: { comparison.style }, set: { comparison.style = $0 })) {
                    Text("통합").tag(ComparisonModel.Style.unified)
                    Text("나란히").tag(ComparisonModel.Style.sideBySide)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("compare-mode")
                Toggle("순서 변경 표시", isOn: Binding(get: { comparison.showsReorder }, set: { comparison.showsReorder = $0 }))
                    .toggleStyle(.checkbox)
                Toggle("바뀐 항목만 보기", isOn: Binding(get: { comparison.changedOnly }, set: { comparison.changedOnly = $0 }))
                    .toggleStyle(.checkbox)
                // Esc: 초점이 대상 메뉴·트리 어디에 있어도 비교를 닫는다. 시트는 별도 창이라 시트의 Esc가 먼저다.
                Button("비교 닫기") { model.closeComparison() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("compare-close")
            }
            HStack(spacing: 8) {
                TargetMenu(model: model, side: .before)
                    .accessibilityIdentifier("compare-before")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TargetMenu(model: model, side: .after)
                    .accessibilityIdentifier("compare-after")
                Spacer()
                Text(comparison.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("compare-summary")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        // 컨테이너로 묶어야 안쪽 버튼·메뉴의 식별자를 덮어쓰지 않는다.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compare-bar")
    }
}

/// 비교 대상 메뉴: '현재 구성'과 revision 목록(최신이 위). 고른 그대로 두고 뒤바꾸지 않는다.
private struct TargetMenu: View {
    enum Side { case before, after }
    let model: BoardBrowserModel
    let side: Side

    var body: some View {
        let comparison = model.comparison
        let current = side == .before ? comparison.before : comparison.after
        Menu(current.map(comparison.targetText) ?? "") {
            Button("현재 구성") { choose(.current) }
            Divider()
            ForEach(comparison.targetChoices, id: \.id) { summary in
                Button(comparison.choiceText(summary)) { choose(.revision(summary.id)) }
            }
        }
        .fixedSize()
        .accessibilityLabel(side == .before ? String(localized: "이전 구성") : String(localized: "이후 구성"))
    }

    private func choose(_ target: ComparisonTarget) {
        Task {
            if side == .before { await model.comparison.setBefore(target) } else { await model.comparison.setAfter(target) }
        }
    }
}

/// 트리 맨 위 'Board 이름' 행(19.3). 나란히 보기에서는 그 열 구성의 Board 이름과 짧은 문구 '이름'을 보인다(19.5).
private struct BoardNameRow: View {
    let model: BoardBrowserModel
    let side: ComparisonTree.Side?

    var body: some View {
        let comparison = model.comparison
        if let side {
            HStack {
                Label { Text(comparison.boardName(side)).lineLimit(1) } icon: { Image(.fianchettoBoard) }
                Spacer(minLength: 8)
                Label(comparison.shortKindText(.renamed), systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(comparison.boardNameAccessibilityLabel(side))
        } else {
            HStack {
                Label { Text("Board 이름") } icon: { Image(.fianchettoBoard) }
                Spacer()
                Label("이름 변경", systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// 비교 트리 행: 이름(제거는 취소선)과 행 끝의 변화 기호 + 문구. 색만으로 구분하지 않는다.
/// 나란히 보기는 짧은 문구를 쓴다(19.5).
private struct ComparisonRowView: View {
    let model: BoardBrowserModel
    let row: ComparisonRow
    let short: Bool

    var body: some View {
        let comparison = model.comparison
        // 트리 행(NodeRow)과 같이 Label 아이콘 자리에 그려 목록의 강조색을 같이 받는다.
        Label {
            HStack(spacing: 8) {
                Text(row.node.displayName)
                    .strikethrough(row.isRemoved)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let first = comparison.visibleKinds(row).first {
                    Label(short ? comparison.shortChangeText(row) : comparison.changeText(row), systemImage: ComparisonModel.kindSymbol(first))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            TileIconView(icon: TileIcon.of(row.node, style: model.bishopIconStyle))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.comparisonAccessibilityLabel(row))
        .accessibilityIdentifier("compare-row-\(row.node.displayName)")
    }
}

/// 인스펙터 항목 탭의 '변경 내용'(19.4): 고른 비교 행의 바뀐 값만 보인다.
struct ComparisonDetailView: View {
    let model: BoardBrowserModel

    var body: some View {
        let comparison = model.comparison
        let lines = comparison.detailLines
        switch comparison.detailState {
        case .noSelection:
            ContentUnavailableView("항목을 고르세요", systemImage: "sidebar.right")
        case .unchanged:
            ContentUnavailableView("바뀐 내용 없음", systemImage: "equal.circle")
        case .changed:
            // 긴 경로가 인스펙터 열의 최소 폭을 밀어 올리지 않게 라벨 아래 최대 두 줄·가운데 줄임으로 보인다(W18 충돌과 같은 위험).
            VStack(alignment: .leading, spacing: 8) {
                // 어떤 항목의 상세인지: 기호와 이름(이름이 바뀌었으면 이후 이름, 제거면 당시 이름).
                DetailHeader(model: model)
                Text("변경 내용")
                    .font(.headline)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        if !line.label.isEmpty {
                            Text(line.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(line.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .help(line.text)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("compare-details")
        }
    }
}

/// '변경 내용' 머리글: 고른 항목의 기호와 이름. 'Board 이름' 행이면 Board 기호.
private struct DetailHeader: View {
    let model: BoardBrowserModel

    var body: some View {
        switch model.comparison.selection {
        case .boardName:
            Label { Text("Board 이름") } icon: { Image(.fianchettoBoard) }
                .font(.title3)
        case .row:
            if let row = model.comparison.selectedRow {
                Label {
                    Text(row.node.displayName)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } icon: {
                    TileIconView(icon: TileIcon.of(row.node, style: model.bishopIconStyle))
                }
                .font(.title3)
            }
        case nil:
            EmptyView()
        }
    }
}
