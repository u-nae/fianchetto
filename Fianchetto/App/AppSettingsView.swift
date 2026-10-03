import SwiftUI

/// 설정 창(⌘,). 화면 설정만 있으며 revision을 만들지 않는다.
struct AppSettingsView: View {
    let model: BoardBrowserModel?

    var body: some View {
        Form {
            if let model {
                Picker("Bishop 아이콘", selection: Binding(get: { model.bishopIconStyle }, set: { model.bishopIconStyle = $0 })) {
                    Text("기호(기본)").tag(BishopIconStyle.symbol)
                    Text("파일 종류 아이콘").tag(BishopIconStyle.fileType)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("bishop-icon-style")
                Text("파일 종류 아이콘은 기록된 경로의 확장자로 정한 일반 아이콘이며 파일을 열어 보지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
