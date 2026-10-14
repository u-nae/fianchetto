import SwiftUI

/// 복원 확인 시트(W20, 0034): 현재 구성에서 고른 과거 구성으로 바뀌는 내용을 보이고 '복원'으로 확정한다.
/// 변화는 기호 + 문구로 알리고 색에 기대지 않는다. 같은 구성이면 '닫기'만 둔다.
struct RestoreSheet: View {
    let model: BoardBrowserModel
    let preview: RestorePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(preview.title)
                .font(.headline)
                .accessibilityIdentifier("restore-sheet-title")
            Text(ChangeWording.arrow(preview.beforeText, preview.afterText))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if preview.isIdentical {
                Text("현재와 같은 구성입니다")
                    .accessibilityIdentifier("restore-identical")
            } else {
                Text(preview.summaryText)
                    .font(.callout.bold())
                    .accessibilityIdentifier("restore-summary")
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let boardName = preview.boardNameText {
                            // 'Board 이름' 행: Board 기호 + 'Board 이름', 행 끝 pencil '이름 변경', 둘째 줄 '이전 → 이후'(16.3).
                            RestoreRowLayout(
                                name: Text("Board 이름"), symbol: ChangeWording.kindSymbol(.renamed),
                                changeText: String(localized: "이름 변경"), valueTexts: [boardName]
                            ) {
                                Image(.fianchettoBoard)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(String(localized: "\(String(localized: "Board 이름")), \(boardName)"))
                            .accessibilityIdentifier("restore-board-name")
                        }
                        ForEach(preview.rows) { row in
                            RestoreRowLayout(name: Text(row.name), symbol: row.symbol, changeText: row.changeText, valueTexts: row.valueTexts) {
                                // 트리 행(NodeRow)·비교 행과 같은 아이콘. 행 앞에 변화 기호를 두지 않는다(16.3).
                                TileIconView(icon: TileIcon.of(row.node, style: model.bishopIconStyle))
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(row.accessibilityLabel)
                            .accessibilityIdentifier("restore-row-\(row.name)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            }
            HStack {
                Spacer()
                if preview.isIdentical {
                    Button("닫기") { model.cancelRestore() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("restore-cancel")
                } else {
                    Button("취소", role: .cancel) { model.cancelRestore() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("restore-cancel")
                    Button("복원") { Task { await model.confirmRestore() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canConfirmRestore)
                        .accessibilityIdentifier("restore-confirm")
                }
            }
        }
        .padding()
        .frame(width: 480)
    }
}

/// 복원 시트의 한 행(DESIGN.md 16.3, 비교 행 19.3·19.4와 같은 문법): 아이콘 자리 + 이름, 행 끝 변화 기호 + 문구,
/// 그 아래 값 줄은 이름과 같은 들여쓰기로 왼쪽 정렬하고 긴 경로·URL은 줄바꿈한다.
private struct RestoreRowLayout<Icon: View>: View {
    let name: Text
    let symbol: String
    let changeText: String
    let valueTexts: [String]
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name.lineLimit(1)
                    Spacer(minLength: 8)
                    Label(changeText, systemImage: symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ForEach(Array(valueTexts.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } icon: {
            icon()
        }
    }
}
