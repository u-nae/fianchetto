import Foundation

enum TargetIdentity: Sendable {
    case sameTarget
    case differentTarget
    case undetermined
}

/// 실제 대상의 파일 시스템 식별자. Platform 어댑터가 불투명한 바이트 값으로 넘기며, 확정 시점에만 쓰고 저장하지 않는다(0004).
struct FileSystemIdentity: Hashable, Sendable {
    var file: Data?
    var volume: Data?
}

/// 결정표 target_identity: 파일 식별자와 볼륨 식별자를 함께 본다. 경로 문자열은 입력이 아니다.
enum TargetIdentityRule {
    enum Comparison: Sendable {
        case same
        case different
        /// 어느 한쪽이라도 식별자를 얻지 못했다.
        case unavailable
    }

    static func compare(_ old: Data?, _ new: Data?) -> Comparison {
        guard let old, let new else { return .unavailable }
        return old == new ? .same : .different
    }

    static func decide(fileIdentifier: Comparison, volumeIdentifier: Comparison) -> TargetIdentity {
        if fileIdentifier == .unavailable || volumeIdentifier == .unavailable { return .undetermined } // R1·R2
        if fileIdentifier == .same && volumeIdentifier == .same { return .sameTarget } // R3
        return .differentTarget // R4·R5
    }

    static func identity(old: FileSystemIdentity, new: FileSystemIdentity) -> TargetIdentity {
        decide(fileIdentifier: compare(old.file, new.file), volumeIdentifier: compare(old.volume, new.volume))
    }
}
