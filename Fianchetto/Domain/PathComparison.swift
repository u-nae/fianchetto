import Foundation

/// 당시 경로와 현재 위치 비교(0003, W18). 디스크에 접근하지 않고 경로 글자만 표준화한다.
/// 심볼릭 링크 해석(/var ↔ /private/var 등)은 디스크 접근이라 호출한 곳이 먼저 한다.
enum PathComparison {
    /// '.'·'..'·빈 구성 요소와 끝 '/'를 정리한 절대 경로. 대소문자는 바꾸지 않는다.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    static func isSameLocation(_ lhs: String, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }
}
