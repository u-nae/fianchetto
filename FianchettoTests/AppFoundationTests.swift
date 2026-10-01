import Foundation
import Testing
@testable import Fianchetto

@Suite("앱 기반 (W01)")
struct AppFoundationTests {
    @Test("[F-W01-1] 앱 번들의 개발 언어는 한국어다")
    func bundleDevelopmentLanguageIsKorean() {
        #expect(Bundle.main.developmentLocalization == "ko")
    }

    @Test("[F-W01-1] 로그 서브시스템은 앱 bundle identifier이다")
    func logSubsystemIsBundleIdentifier() {
        #expect(AppLog.subsystem == Bundle.main.bundleIdentifier)
    }

    @Test("[F-W01-1] 로그 카테고리 이름은 비어 있지 않고 서로 다르다")
    func logCategoriesAreDistinct() {
        let names = AppLog.Category.allCases.map(\.rawValue)
        #expect(!names.isEmpty)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }
}
