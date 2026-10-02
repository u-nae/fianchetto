import SwiftUI

/// 연결 상태의 화면 표현(기호와 의미 색). 문구는 BoardBrowserModel.statusText가 정한다.
/// 값은 디자인 결정 0010을 따른다. 의미 색은 기호에만 칠하고 문구는 .secondary로 둔다(라이트 모드 주황 글자 대비 부족).
struct LinkStatusPresentation: Equatable {
    var systemImage: String
    var symbolColor: Color

    /// 정상은 표시하지 않는다.
    static func of(_ status: LinkStatus) -> LinkStatusPresentation? {
        switch status {
        case .healthy: nil
        case .accessRequired: LinkStatusPresentation(systemImage: "lock", symbolColor: .orange)
        case .missing: LinkStatusPresentation(systemImage: "xmark.circle", symbolColor: .red)
        case .volumeUnavailable: LinkStatusPresentation(systemImage: "externaldrive.badge.xmark", symbolColor: .orange)
        case .checkFailed: LinkStatusPresentation(systemImage: "questionmark.circle", symbolColor: .secondary)
        }
    }
}

/// 트리 행·상세 영역의 상태 표시: 기호(의미 색) + 문구(.secondary). 색만으로 구분하지 않는다.
struct LinkStatusLabel: View {
    let text: String
    let presentation: LinkStatusPresentation

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: presentation.systemImage).foregroundStyle(presentation.symbolColor)
        }
        .font(.caption)
    }
}
