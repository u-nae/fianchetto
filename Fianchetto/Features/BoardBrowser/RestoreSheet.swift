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
                            HStack(alignment: .firstTextBaseline) {
                                Label { Text("Board 이름") } icon: { Image(.fianchettoBoard) }
                                Spacer(minLength: 8)
                                Text(boardName).font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(String(localized: "\(String(localized: "Board 이름")), \(boardName)"))
                            .accessibilityIdentifier("restore-board-name")
                        }
                        ForEach(preview.rows) { row in
                            HStack(alignment: .firstTextBaseline) {
                                Label(row.name, systemImage: row.symbol)
                                Spacer(minLength: 8)
                                Text(row.changeText).font(.caption).foregroundStyle(.secondary)
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
