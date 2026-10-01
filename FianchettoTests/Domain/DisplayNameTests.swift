import Foundation
import Testing
@testable import Fianchetto

@Suite("표시 이름 규칙 (W02)")
struct DisplayNameTests {
    @Test(
        "[W02-display-name-trimmed] 표시 이름은 앞뒤 공백을 정리하고 내부 공백은 유지한다",
        arguments: [
            ("backend", "backend"),
            ("  backend", "backend"),
            ("backend\n", "backend"),
            ("\t인증 리팩토링 1차\u{3000}", "인증 리팩토링 1차"),
            ("서비스  A", "서비스  A"),
        ]
    )
    func displayNameIsTrimmed(input: String, expected: String) throws {
        #expect(try DisplayName.normalize(input) == expected)
    }

    @Test("[W02-blank-name-rejected] 비었거나 공백만 있는 표시 이름은 만들 수 없다", arguments: ["", "   ", "\n\t", "\u{3000}"])
    func blankDisplayNameIsRejected(input: String) {
        #expect(throws: DisplayNameError.blank) { try DisplayName.normalize(input) }
    }

    @Test("[W02-project-name-rules] 프로젝트 이름도 앞뒤 공백을 정리해 만든다")
    func projectNameIsTrimmed() throws {
        #expect(try ProjectName.normalize("  서비스 A  ") == "서비스 A")
    }

    @Test("[W02-project-name-blank-rejected] 공백만 있는 프로젝트 이름은 만들 수 없다")
    func blankProjectNameIsRejected() {
        #expect(throws: DisplayNameError.blank) { try ProjectName.normalize("   ") }
    }
}
