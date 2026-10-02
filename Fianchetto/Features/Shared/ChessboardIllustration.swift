import SwiftUI

/// 빈 화면용 장식 체스판(0016). 밝은 칸·어두운 칸 두 색만 쓰며 글자를 넣지 않는다.
/// 색은 테마 토큰을 따르므로 다크·고대비에서 Asset Catalog 변형이 그대로 적용된다. 의미가 없는 장식이라 VoiceOver에서 숨긴다.
struct ChessboardIllustration: View {
    private let squares = 4

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<squares, id: \.self) { row in
                GridRow {
                    ForEach(0..<squares, id: \.self) { column in
                        Rectangle()
                            .fill((row + column).isMultiple(of: 2) ? Color(.themeLine) : Color(.accent))
                    }
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("체스판") {
    ChessboardIllustration()
        .padding()
}

#Preview("체스판 · 다크") {
    ChessboardIllustration()
        .padding()
        .preferredColorScheme(.dark)
}
#endif
