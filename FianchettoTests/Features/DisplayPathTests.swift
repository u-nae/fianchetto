import Testing
@testable import Fianchetto

@Suite("카드 경로 표시(W18)")
struct DisplayPathTests {
    @Test("[W18-location-card] 사용자 홈 아래 경로는 ~로 줄이고 그 밖은 그대로 둔다", arguments: [
        ("/Users/kim/Documents/api", "~/Documents/api"),
        ("/Users/kim", "~"),
        ("/Users/kimberly/api", "/Users/kimberly/api"),
        ("/Volumes/Work/api", "/Volumes/Work/api"),
    ])
    func abbreviated(path: String, expected: String) {
        #expect(DisplayPath.abbreviated(path, home: "/Users/kim") == expected)
    }

    @Test("[W18-location-card] 홈을 모르거나 홈이 루트면 줄이지 않는다")
    func noHome() {
        #expect(DisplayPath.abbreviated("/Users/kim/api", home: nil) == "/Users/kim/api")
        #expect(DisplayPath.abbreviated("/Users/kim/api", home: "/") == "/Users/kim/api")
    }
}
