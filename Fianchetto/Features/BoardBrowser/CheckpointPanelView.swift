import SwiftUI

/// 과거 구성 띠 아래 체크포인트 패널(W22, DESIGN.md 16.6): 깃발 + 제목 + 저장 시각 + 접기 버튼, 아래 '진행 메모'·'다음 할 일' 두 열.
/// 비어 있는 열은 빠지고, 접으면 첫 줄만 남는다. 접힘은 화면 상태라 저장하지 않는다. 비교 중에는 그리지 않는다.
struct CheckpointPanelView: View {
    let model: BoardBrowserModel
    let panel: BoardBrowserModel.CheckpointPanel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(Color(.themeAccentText))
                    Text(panel.title)
                        .font(.headline)
                    Text(panel.savedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button { model.toggleCheckpointPanel() } label: {
                        Image(systemName: panel.isCollapsed ? "chevron.down" : "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .help(model.checkpointToggleHelp)
                    .accessibilityLabel(model.checkpointToggleHelp)
                    .accessibilityIdentifier("checkpoint-panel-toggle")
                }
                if !panel.isCollapsed, panel.progressNote != nil || panel.nextSteps != nil {
                    // 내용이 짧으면 내용 높이만큼, 길면 200(기본 창 높이의 약 1/3)에서 멈추고 스크롤한다(16.6의 상한).
                    ViewThatFits(in: .vertical) {
                        columns
                        ScrollView { columns }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            Divider()
        }
        // 컨테이너로 묶어야 식별자가 첫 자식(깃발)이 아니라 패널에 붙고, 안의 문구를 패널 아래에서 찾을 수 있다.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checkpoint-panel")
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 16) {
            column("진행 메모", panel.progressNote)
            column("다음 할 일", panel.nextSteps)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func column(_ label: LocalizedStringKey, _ body: String?) -> some View {
        if let body {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(body)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
