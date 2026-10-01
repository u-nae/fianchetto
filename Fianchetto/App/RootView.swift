import SwiftUI

/// 기본 창의 최상위 View. Board 탐색 화면(W07)이 들어오기 전까지 빈 창을 유지한다.
struct RootView: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 720, minHeight: 480)
    }
}
