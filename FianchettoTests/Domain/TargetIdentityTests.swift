import Foundation
import Testing
@testable import Fianchetto

@Suite("같은 대상 판정 (W03, 0004)")
struct TargetIdentityTests {
    typealias Comparison = TargetIdentityRule.Comparison

    @Test("[W03-target-identity-decision] 식별자 비교로 같은 대상 여부를 판정한다(R1~R5, 9조합)", arguments: [
        (Comparison.same, Comparison.same, TargetIdentity.sameTarget),
        (.same, .different, .differentTarget),
        (.different, .same, .differentTarget),
        (.different, .different, .differentTarget),
        (.unavailable, .same, .undetermined),
        (.same, .unavailable, .undetermined),
        (.unavailable, .different, .undetermined),
        (.different, .unavailable, .undetermined),
        (.unavailable, .unavailable, .undetermined),
    ])
    func decision(file: Comparison, volume: Comparison, expected: TargetIdentity) {
        #expect(TargetIdentityRule.decide(fileIdentifier: file, volumeIdentifier: volume) == expected)
    }

    static let f1 = Data([1]), f2 = Data([2]), v1 = Data([10]), v2 = Data([20])

    @Test("[W03-target-identity-from-identifiers] 식별자 쌍을 비교 입력으로 바꾼다", arguments: [
        (FileSystemIdentity(file: f1, volume: v1), FileSystemIdentity(file: f1, volume: v1), Comparison.same, Comparison.same, TargetIdentity.sameTarget),
        (FileSystemIdentity(file: f1, volume: v1), FileSystemIdentity(file: f2, volume: v1), .different, .same, .differentTarget),
        (FileSystemIdentity(file: f1, volume: v1), FileSystemIdentity(file: f1, volume: v2), .same, .different, .differentTarget),
        (FileSystemIdentity(file: nil, volume: v1), FileSystemIdentity(file: f1, volume: v1), .unavailable, .same, .undetermined),
        (FileSystemIdentity(file: f1, volume: v1), FileSystemIdentity(file: f1, volume: nil), .same, .unavailable, .undetermined),
        (FileSystemIdentity(file: nil, volume: nil), FileSystemIdentity(file: nil, volume: nil), .unavailable, .unavailable, .undetermined),
    ])
    func fromIdentifiers(
        old: FileSystemIdentity, new: FileSystemIdentity,
        file: Comparison, volume: Comparison, expected: TargetIdentity
    ) {
        #expect(TargetIdentityRule.compare(old.file, new.file) == file)
        #expect(TargetIdentityRule.compare(old.volume, new.volume) == volume)
        #expect(TargetIdentityRule.identity(old: old, new: new) == expected)
    }

    @Test("[W03-target-identity-ignores-path] 경로가 같아도 식별자가 다르면 다른 대상이다")
    func pathIsNotUsed() {
        // 판정 입력에는 경로가 없다. 같은 경로 "/dev/legacy-api"에 다른 파일이 있는 경우다.
        let old = FileSystemIdentity(file: Self.f1, volume: Self.v1)
        let new = FileSystemIdentity(file: Self.f2, volume: Self.v1)

        #expect(TargetIdentityRule.identity(old: old, new: new) == .differentTarget)
    }
}
