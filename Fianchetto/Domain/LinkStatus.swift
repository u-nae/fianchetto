import Foundation

/// Bishop의 연결 상태(PRD §6-H). 화면 세션 동안만 기억하고 저장하지 않는다.
/// 근거가 부족하면 checkFailed이며 대상의 존재 여부를 단정하지 않는다.
enum LinkStatus: Equatable, Sendable {
    case healthy
    case accessRequired
    case missing
    case volumeUnavailable
    case checkFailed
}
