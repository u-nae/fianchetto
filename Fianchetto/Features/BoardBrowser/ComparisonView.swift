import SwiftUI

/// 구성 비교 화면(W19, DESIGN.md 19장): 비교 띠와 통합 트리. 표시 전용이며 열기·Finder에서 보기만 한다.
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
        if comparison.isSameTarget {
            ContentUnavailableView("같은 구성입니다", systemImage: "equal.circle")
        } else if comparison.hasNoChange {
            ContentUnavailableView("변화 없음", systemImage: "equal.circle", description: Text("두 구성이 같습니다."))
        } else if comparison.isFilteredEmpty {
            ContentUnavailableView(
                "표시할 변화 없음", systemImage: "line.3.horizontal.decrease.circle",
                description: Text("순서 변경 표시를 켜면 순서만 바뀐 항목이 보입니다.")
            )
        } else {
            let rows = comparison.shownRows.map(ComparisonListItem.init)
            List(selection: Binding(get: { comparison.selection }, set: { comparison.selection = $0 })) {
                if comparison.showsBoardNameRow {
                    BoardNameRow()
                        .tag(ComparisonModel.Selection.boardName)
                }
                OutlineGroup(rows, children: \.children) { item in
                    ComparisonRowView(model: model, row: item.row)
                        .tag(ComparisonModel.Selection.row(item.row.id))
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
            .accessibilityIdentifier("compare-tree")
        }
    }

    private func run(_ id: UUID, _ action: @escaping @MainActor () async -> Void) {
        comparison.selection = .row(id)
        Task { await action() }
    }
}

/// OutlineGroup용 행 묶음: 하위가 없으면 nil이라 펼침 삼각형을 그리지 않는다.
private struct ComparisonListItem: Identifiable {
    let row: ComparisonRow
    var id: UUID { row.id }
    var children: [ComparisonListItem]? { row.children.isEmpty ? nil : row.children.map(ComparisonListItem.init) }
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
                Toggle("순서 변경 표시", isOn: Binding(get: { comparison.showsReorder }, set: { comparison.showsReorder = $0 }))
                    .toggleStyle(.checkbox)
                Toggle("바뀐 항목만 보기", isOn: Binding(get: { comparison.changedOnly }, set: { comparison.changedOnly = $0 }))
                    .toggleStyle(.checkbox)
                Button("비교 닫기") { model.closeComparison() }
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

/// 트리 맨 위 'Board 이름' 행(19.3).
private struct BoardNameRow: View {
    var body: some View {
        HStack {
            Label("Board 이름", systemImage: "square.grid.2x2")
            Spacer()
            Label("이름 변경", systemImage: "pencil")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 통합 트리 행: 이름(제거는 취소선)과 행 끝의 변화 기호 + 문구. 색만으로 구분하지 않는다.
private struct ComparisonRowView: View {
    let model: BoardBrowserModel
    let row: ComparisonRow

    var body: some View {
        let comparison = model.comparison
        HStack(spacing: 8) {
            TileIconView(icon: TileIcon.of(row.node, style: model.bishopIconStyle))
            Text(row.node.displayName)
                .strikethrough(row.isRemoved)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let first = comparison.visibleKinds(row).first {
                Label(comparison.changeText(row), systemImage: ComparisonModel.kindSymbol(first))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
        let lines = model.comparison.detailLines
        if lines.isEmpty {
            ContentUnavailableView("항목을 고르세요", systemImage: "sidebar.right")
        } else {
            // 긴 경로가 인스펙터 열의 최소 폭을 밀어 올리지 않게 라벨 아래 최대 두 줄·가운데 줄임으로 보인다(W18 충돌과 같은 위험).
            VStack(alignment: .leading, spacing: 8) {
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
