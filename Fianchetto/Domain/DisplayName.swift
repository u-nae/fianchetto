import Foundation

enum DisplayNameError: Error, Equatable, Sendable {
    case blank
}

/// Node 표시 이름 규칙: 앞뒤 공백·줄바꿈을 정리하고, 정리 후 비어 있으면 거부한다. 같은 이름의 형제는 허용한다.
enum DisplayName {
    static func normalize(_ input: String) throws(DisplayNameError) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .blank }
        return trimmed
    }
}

/// 프로젝트 이름은 Node 표시 이름과 같은 규칙을 따른다.
enum ProjectName {
    static func normalize(_ input: String) throws(DisplayNameError) -> String {
        try DisplayName.normalize(input)
    }
}
