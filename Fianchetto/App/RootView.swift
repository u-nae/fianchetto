import SwiftUI

/// 기본 창의 최상위 View. 단위 테스트 호스트에서는 모델이 없어 빈 창을 유지한다.
struct RootView: View {
    let model: BoardBrowserModel?

    var body: some View {
        if let model {
            BoardBrowserView(model: model)
                .task { await model.start() }
        } else {
            Color.clear.frame(minWidth: 720, minHeight: 480)
        }
    }
}
