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
                            .contextMenu { compareMenu(.current) }
                        ForEach(history.sections) { section in
                            Section(section.title) {
                                ForEach(section.entries) { entry in
                                    switch entry {
                                    case let .revision(row):
                                        HistoryRowView(history: history, row: row)
                                            .tag(HistoryPanelModel.Selection.revision(row.id))
                                            .contextMenu { compareMenu(.revision(row.id)) }
                                            .id(row.id)
                                            .onAppear {
                                                // 마지막 행이 체크포인트 행이어도 다음 묶음을 불러온다(W22).
                                                if entry.id == history.entries.last?.id { Task { await history.loadMore() } }
                                            }
                                    case .checkpoint:
                                        EmptyView()
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

extension HistoryTabView {
    /// 이력 행 오른쪽 클릭 '이 기록과 비교'(W19): 그 행과 지금 보는 구성의 비교를 연다.
    @ViewBuilder
    func compareMenu(_ row: HistoryPanelModel.Selection) -> some View {
        Button("이 기록과 비교") { Task { await model.compareRecord(row) } }
            .disabled(!model.canCompareRecord(row))
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
                    PathLine(label: model.recordedPathLabel, path: PathComparison.normalize(recorded))
                }
                switch card.location {
                case let .resolved(path, differs):
                    PathLine(label: model.currentLocationLabel, path: path)
                    if differs {
                        Label(model.movedLocationText, systemImage: "arrow.turn.down.right")
                            .font(.caption)
                    }
                case let .unresolved(status):
                    if let presentation = LinkStatusPresentation.of(status) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.currentLocationLabel).font(.caption).foregroundStyle(.secondary)
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
                    .lineLimit(3)
            case .webLink:
                if let url = card.url {
                    PathLine(label: model.recordedURLLabel, path: url, abbreviatesHome: false)
                }
                Button("열기") { Task { await model.openSelected() } }
            case .group:
                EmptyView()
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityIdentifier("past-item-card")
    }
}

/// 카드의 경로 한 줄: 위에 작은 라벨, 아래에 최대 두 줄·가운데 줄임 경로(홈은 ~). 전체 경로는 도움말 풍선으로 본다.
/// 긴 경로가 인스펙터 열의 최소 폭을 밀어 올리지 않게 폭을 고정하지 않는다(분할 뷰 제약 갱신이 반복되던 문제).
private struct PathLine: View {
    let label: String
    let path: String
    var abbreviatesHome = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(abbreviatesHome ? DisplayPath.abbreviated(path) : path)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .help(path)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 화면에 보일 경로: 사용자 홈 아래면 ~로 줄인다. 앱 샌드박스의 홈(컨테이너)이 아니라 실제 사용자 홈을 쓴다.
enum DisplayPath {
    private static let home: String? = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }

    static func abbreviated(_ path: String, home: String? = DisplayPath.home) -> String {
        guard let home, !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
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
