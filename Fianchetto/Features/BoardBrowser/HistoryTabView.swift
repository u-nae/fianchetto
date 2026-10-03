import SwiftUI

/// 인스펙터 '이력' 탭(DESIGN.md 16.2): 날짜로 찾기, '현재 구성' 행, 기록이 있는 날의 구역과 revision 행.
struct HistoryTabView: View {
    let history: HistoryPanelModel
    let model: BoardBrowserModel

    var body: some View {
        let selection = history.selection
        let notice = history.notice
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // 인스펙터 폭이 좁아도 줄이 깨지지 않게 라벨을 칸 위에 둔다.
                Text("날짜로 찾기")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                DatePicker(
                    "날짜로 찾기",
                    selection: Binding(get: { history.lookupDate }, set: { picked in Task { await history.lookUp(picked) } }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.field)
                .labelsHidden()
                .accessibilityIdentifier("date-lookup")
                if history.lookupFoundNothing {
                    Label(history.lookupNothingText, systemImage: "calendar.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            if history.listFailed {
                ContentUnavailableView(history.noticeText(.loadFailed), systemImage: "exclamationmark.triangle")
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(get: { Optional(selection) }, set: { next in
                        if let next { Task { await history.select(next) } }
                    })) {
                        Label("현재 구성", systemImage: "square.stack.3d.up")
                            .tag(HistoryPanelModel.Selection.current)
                        ForEach(history.sections) { section in
                            Section(section.title) {
                                ForEach(section.rows) { row in
                                    HistoryRowView(history: history, row: row)
                                        .tag(HistoryPanelModel.Selection.revision(row.id))
                                        .id(row.id)
                                        .onAppear {
                                            if row.id == history.rows.last?.id { Task { await history.loadMore() } }
                                        }
                                }
                            }
                        }
                    }
                    .onChange(of: history.scrollTarget) { _, target in
                        if let target { proxy.scrollTo(target, anchor: .center) }
                    }
                }
            }
            if let card = model.pastItemCard {
                Divider()
                PastItemCardView(model: model, card: card)
            }
        }
        .accessibilityIdentifier("history-tab")
        .alert(
            notice.map(history.noticeText) ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { history.dismissNotice() } })
        ) {
            Button("확인", role: .cancel) { history.dismissNotice() }
        }
    }
}

/// '고른 항목' 카드(16.2): 과거 구성에서 고른 항목의 이름, 당시 경로, 현재 위치(또는 상태), 다른 위치 표시, 열기.
private struct PastItemCardView: View {
    let model: BoardBrowserModel
    let card: BoardBrowserModel.PastItemCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("고른 항목")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(card.name)
                .font(.headline)
            switch card.kind {
            case .file, .folder:
                if let recorded = card.recordedPath {
                    LabeledContent(model.recordedPathLabel) { Text(recorded).textSelection(.enabled) }
                }
                switch card.location {
                case let .resolved(path, differs):
                    LabeledContent(model.currentLocationLabel) { Text(path).textSelection(.enabled) }
                    if differs {
                        Label(model.movedLocationText, systemImage: "arrow.turn.down.right")
                            .font(.caption)
                    }
                case let .unresolved(status):
                    if let presentation = LinkStatusPresentation.of(status) {
                        LabeledContent(model.currentLocationLabel) {
                            LinkStatusLabel(text: model.statusText(status), presentation: presentation)
                        }
                    }
                case nil:
                    EmptyView()
                }
                HStack {
                    Button("열기") { Task { await model.openSelected() } }
                    Button("Finder에서 보기") { Task { await model.revealSelected() } }
                }
                Text(model.currentContentNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .webLink:
                if let url = card.url {
                    LabeledContent(model.recordedURLLabel) { Text(url).textSelection(.enabled) }
                }
                Button("열기") { Task { await model.openSelected() } }
            case .group:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityIdentifier("past-item-card")
    }
}

/// revision 행: 왼쪽 기호 + 원인 문구, 아래 줄 '#순번 · 시각'. VoiceOver는 한 요소로 읽는다.
private struct HistoryRowView: View {
    let history: HistoryPanelModel
    let row: HistoryPanelModel.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: history.causeSymbol(row))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(history.causeText(row))
                Text(history.caption(row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(history.accessibilityLabel(row))
        .accessibilityIdentifier("revision-row-\(row.summary.sequence)")
    }
}
