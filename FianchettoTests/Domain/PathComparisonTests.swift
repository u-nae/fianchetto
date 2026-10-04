import Testing
@testable import Fianchetto

@Suite("당시 경로와 현재 위치 비교(W18)")
struct PathComparisonTests {
    @Test("[W18-location-card] 끝 '/'·'.'·'..'·중복 '/'만 다른 경로는 같은 위치다", arguments: [
        ("/dev/legacy-api", "/dev/legacy-api/"),
        ("/dev/legacy-api", "/dev//legacy-api"),
        ("/dev/legacy-api", "/dev/./legacy-api"),
        ("/dev/legacy-api", "/dev/tmp/../legacy-api"),
    ])
    func sameLocation(lhs: String, rhs: String) {
        #expect(PathComparison.isSameLocation(lhs, rhs))
    }

    @Test("[W18-location-card] 다른 폴더나 다른 이름은 다른 위치다", arguments: [
        ("/dev/legacy-api", "/archive/legacy-api"),
        ("/dev/legacy-api", "/dev/legacy-api-2"),
        ("/dev/legacy-api", "/dev/Legacy-API"),
        ("/dev/legacy-api", "/"),
    ])
    func differentLocation(lhs: String, rhs: String) {
        #expect(!PathComparison.isSameLocation(lhs, rhs))
    }

    @Test("[W18-location-card] 표준화한 경로는 끝 '/'가 없고 최상위는 '/'다")
    func normalized() {
        #expect(PathComparison.normalize("/dev/legacy-api/") == "/dev/legacy-api")
        #expect(PathComparison.normalize("/") == "/")
        #expect(PathComparison.normalize("/..") == "/")
    }
}
