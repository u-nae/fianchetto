import SwiftUI

/// 과거 구성으로 새 Board를 만드는 시트(W21, DESIGN.md 16.3): 'Board 만들기' 시트와 같은 골격.
/// 기본 이름은 그 revision의 Board 이름에 '사본'을 붙인 것이고 전체 선택된 채 연다. 저장 실패는 입력을 유지한 채 알린다.
struct DuplicateSheet: View {
    @Bindable var model: BoardBrowserModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.duplication?.title ?? "")
                .font(.headline)
                .accessibilityIdentifier("duplicate-sheet-title")
            Text(model.duplication?.subtitle ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            TextField("Board 이름", text: Binding(
                get: { model.duplication?.name ?? "" }, set: { model.duplication?.name = $0 }
            ))
            .accessibilityIdentifier("duplicate-name-field")
            .focused($nameFocused)
            .onSubmit { if model.canConfirmDuplicate { confirm() } }
            Text("새 Board는 이 구성으로 시작하고 이력은 새로 쌓입니다. 원래 Board는 바뀌지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.duplication?.message {
                Text(message == .nameRequired ? "이름을 입력하세요." : "저장하지 못했습니다. 다시 시도하세요.")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("취소", role: .cancel) { model.cancelDuplicate() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!model.canCancelDuplicate)
                    .accessibilityIdentifier("duplicate-cancel")
                Button("만들기") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConfirmDuplicate)
                    .accessibilityIdentifier("duplicate-confirm")
            }
        }
        .padding()
        .frame(width: 360)
        .onAppear { nameFocused = true }
    }

    private func confirm() {
        Task { await model.confirmDuplicate() }
    }
}
