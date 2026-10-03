import SwiftUI

/// 인스펙터 '이력' 탭(DESIGN.md 16.2): 날짜로 찾기, '현재 구성' 행, 기록이 있는 날의 구역과 revision 행.
struct HistoryTabView: View {
    let history: HistoryPanelModel

    var body: some View {
        let selection = history.selection
        let notice = history.notice
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                DatePicker(
                    "날짜로 찾기",
                    selection: Binding(get: { history.lookupDate }, set: { picked in Task { await history.lookUp(picked) } }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.field)
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
