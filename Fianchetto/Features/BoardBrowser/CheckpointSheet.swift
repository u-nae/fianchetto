import SwiftUI

/// 체크포인트 저장 시트(W22, DESIGN.md 16.6): 시트를 열 때 고정한 현재 revision에 제목·진행 메모·다음 할 일을 붙인다.
/// 라벨은 칸 위에 두고 '제목' 칸에 처음 초점을 둔다. 제목 칸의 Return은 '저장', 메모 칸의 Return은 줄바꿈이다.
/// 저장 실패는 입력을 유지한 채 버튼 위에 기호와 문구로 알린다. W23 이미지 첨부 자리는 미리 두지 않는다.
struct CheckpointSheet: View {
    @Bindable var model: BoardBrowserModel
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("체크포인트 저장")
                .font(.headline)
                .accessibilityIdentifier("checkpoint-sheet-title")
            Text(model.checkpointDraft?.subtitle ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 4) {
                Text("제목")
                    .font(.callout)
                TextField("제목", text: binding(\.title), prompt: Text("예: 인증 리팩토링 1차 완료"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                    .onSubmit { if model.canConfirmCheckpoint { confirm() } }
                    .accessibilityIdentifier("checkpoint-title-field")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("진행 메모")
                    .font(.callout)
                editor(binding(\.progressNote), height: 92)
                    .accessibilityIdentifier("checkpoint-memo-field")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("다음 할 일")
                    .font(.callout)
                editor(binding(\.nextSteps), height: 72)
                    .accessibilityIdentifier("checkpoint-next-field")
            }
            Text("저장한 체크포인트는 고칠 수 없습니다. 고치려면 같은 구성에 새로 저장합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.checkpointDraft?.message == .saveFailed {
                Label("저장하지 못했습니다. 입력한 내용은 그대로 있으니 다시 시도하세요.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("checkpoint-save-error")
            }
            HStack {
                Spacer()
                Button("취소", role: .cancel) { model.cancelCheckpoint() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!model.canCancelCheckpoint)
                    .accessibilityIdentifier("checkpoint-cancel")
                Button("저장") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConfirmCheckpoint)
                    .accessibilityIdentifier("checkpoint-save")
            }
        }
        .padding()
        .frame(width: 480)
        .onAppear { titleFocused = true }
    }

    /// 여러 줄 입력 칸: 텍스트 바탕에 구분선 색 테두리, 모서리 5(16.6).
    private func editor(_ text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(height: height)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
    }

    private func binding(_ keyPath: WritableKeyPath<BoardBrowserModel.CheckpointDraft, String>) -> Binding<String> {
        Binding(
            get: { model.checkpointDraft?[keyPath: keyPath] ?? "" },
            set: { model.checkpointDraft?[keyPath: keyPath] = $0 }
        )
    }

    private func confirm() {
        Task { await model.confirmCheckpoint() }
    }
}
