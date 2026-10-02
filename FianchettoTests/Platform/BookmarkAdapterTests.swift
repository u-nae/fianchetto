import Foundation
import Testing
@testable import Fianchetto

@Suite("읽기 전용 북마크 어댑터 (W06)")
struct BookmarkAdapterTests {
    let adapter = BookmarkAdapter(system: FoundationBookmarkSystem())

    // MARK: 생성

    enum Target: String, CaseIterable, Sendable { case file, folder, package }

    @Test("[W06-create-bookmark] 고른 대상에서 북마크를 만들면 종류와 경로를 함께 돌려준다", .tags(.A02), arguments: Target.allCases)
    func createBookmark(target: Target) throws {
        try withTemporaryDirectory { directory throws in
            let (url, kind): (URL, LinkedTarget.Kind) = switch target {
            case .file: (try makeFile(directory, "design.md"), .file)
            case .folder: (try makeFolder(directory, "assets"), .folder)
            case .package: (try makeFolder(directory, "Deck.key"), .file)
            }
            let spelled = URL(filePath: directory.path + "/sub/../" + url.lastPathComponent)

            let creation = try adapter.createBookmark(for: spelled)

            #expect(!creation.bookmarkData.isEmpty)
            #expect(creation.kind == kind)
            #expect(creation.path == url.standardizedFileURL.path)
            #expect(!creation.path.contains("/../"))
        }
    }

    @Test("[W06-create-bookmark] 심볼릭 링크로 고른 대상은 고른 표기의 경로를 기록한다", .tags(.A02))
    func createKeepsSymlinkSpelling() throws {
        try withTemporaryDirectory { directory throws in
            _ = try makeFile(directory, "design.md")
            let link = directory.appending(path: "linked")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)

            let creation = try adapter.createBookmark(for: link.appending(path: "design.md"))

            #expect(creation.path == link.appending(path: "design.md").path)
        }
    }

    @Test("[W06-read-only-options] 북마크는 보안 범위와 읽기 전용 옵션으로 만든다")
    func usesReadOnlySecurityScope() throws {
        let system = FakeBookmarkSystem()
        let adapter = BookmarkAdapter(system: system)

        let creation = try adapter.createBookmark(for: URL(filePath: "/tmp/design.md"))
        _ = try adapter.resolve(creation.bookmarkData)

        let creationOptions = try #require(system.creationOptions.first)
        #expect(creationOptions.contains(.withSecurityScope))
        #expect(creationOptions.contains(.securityScopeAllowOnlyReadAccess))
        let resolutionOptions = try #require(system.resolutionOptions.first)
        #expect(resolutionOptions.contains(.withSecurityScope))
        #expect(resolutionOptions.contains(.withoutUI))
        #expect(resolutionOptions.contains(.withoutMounting))
    }

    @Test("[W06-create-missing-fails] 없는 대상의 북마크는 만들 수 없다")
    func createMissingFails() throws {
        try withTemporaryDirectory { directory throws in
            _ = #expect(throws: BookmarkError.creationFailed) {
                try adapter.createBookmark(for: directory.appending(path: "nothing.md"))
            }
        }
    }

    // MARK: 해석

    @Test("[W06-resolve-same-target] 만든 북마크를 해석하면 같은 대상을 가리킨다", .tags(.A02))
    func resolveSameTarget() throws {
        try withTemporaryDirectory { directory throws in
            let url = try makeFile(directory, "design.md")
            let creation = try adapter.createBookmark(for: url)

            let resolution = try adapter.resolve(creation.bookmarkData)

            #expect(canonical(resolution.url) == canonical(url))
            #expect(resolution.refreshedBookmark == nil)
            #expect(!resolution.refreshFailed)
        }
    }

    @Test("[W06-resolve-moved-refreshes] 대상이 같은 볼륨 안에서 이동해도 해석은 새 위치를 가리키고 갱신 북마크를 준다", .tags(.A02))
    func resolveMovedTarget() throws {
        try withTemporaryDirectory { directory throws in
            let url = try makeFile(directory, "design.md")
            let creation = try adapter.createBookmark(for: url)
            let archive = try makeFolder(directory, "archive")
            let moved = archive.appending(path: "design.md")
            try FileManager.default.moveItem(at: url, to: moved)

            let resolution = try adapter.resolve(creation.bookmarkData)

            #expect(canonical(resolution.url) == canonical(moved))
            let refreshed = try #require(resolution.refreshedBookmark)
            let again = try adapter.resolve(refreshed)
            #expect(canonical(again.url) == canonical(moved))
            #expect(again.refreshedBookmark == nil)
        }
    }

    @Test("[W06-stale-same-path-refreshes] 경로가 그대로여도 시스템이 stale을 알리면 갱신 북마크를 만든다")
    func staleSamePathRefreshes() throws {
        let adapter = BookmarkAdapter(system: FakeBookmarkSystem(.init(isStale: true)))

        let resolution = try adapter.resolve(Data("bookmark".utf8))

        #expect(resolution.url.path == "/tmp/design.md")
        #expect(resolution.refreshedBookmark != nil)
        #expect(!resolution.refreshFailed)
    }

    @Test("[W06-refresh-failure-reported] 갱신 북마크를 만들지 못해도 해석은 성공하고 갱신 실패를 알린다")
    func refreshFailureIsReported() throws {
        let adapter = BookmarkAdapter(system: FakeBookmarkSystem(.init(isStale: true, creationFails: true)))

        let resolution = try adapter.resolve(Data("bookmark".utf8))

        #expect(resolution.url.path == "/tmp/design.md")
        #expect(resolution.refreshedBookmark == nil)
        #expect(resolution.refreshFailed)
    }

    @Test("[W06-resolve-deleted-missing] 대상이 삭제되면 해석은 대상 없음으로 실패한다")
    func resolveDeletedTarget() throws {
        try withTemporaryDirectory { directory throws in
            let url = try makeFile(directory, "design.md")
            let creation = try adapter.createBookmark(for: url)
            try FileManager.default.removeItem(at: url)

            _ = #expect(throws: BookmarkError.resolutionFailed(.missing)) { try adapter.resolve(creation.bookmarkData) }
        }
    }

    @Test("[W06-resolve-garbage-check-failed] 손상된 북마크 바이트는 확인 실패로 분류한다")
    func resolveGarbage() {
        #expect(throws: BookmarkError.resolutionFailed(.checkFailed)) { try adapter.resolve(Data("not a bookmark".utf8)) }
    }

    @Test("[W06-error-kind-mapping] 시스템 오류를 오류 범주로 바꾼다", arguments: [
        (NSCocoaErrorDomain, NSFileNoSuchFileError, BookmarkFailureRule.ErrorKind.noSuchFile),
        (NSCocoaErrorDomain, NSFileReadNoSuchFileError, .noSuchFile),
        (NSCocoaErrorDomain, NSFileReadNoPermissionError, .noPermission),
        (NSPOSIXErrorDomain, Int(ENOENT), .noSuchFile),
        (NSPOSIXErrorDomain, Int(EACCES), .noPermission),
        (NSPOSIXErrorDomain, Int(EPERM), .noPermission),
        (NSCocoaErrorDomain, NSFileReadCorruptFileError, .other),
        (NSURLErrorDomain, -1, .other),
    ])
    func errorKindMapping(domain: String, code: Int, expected: BookmarkFailureRule.ErrorKind) {
        #expect(BookmarkFailureRule.errorKind(NSError(domain: domain, code: code)) == expected)
    }

    @Test("[W06-volume-state] 북마크가 기록한 볼륨 경로로 볼륨 상태를 정한다", arguments: [
        (Result<String?, NSError>.success("/"), BookmarkFailureRule.VolumeState.mounted),
        (.success("/Volumes/분리됨"), .unmounted),
        (.failure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)), .unknown),
        (.success(nil), .unknown),
    ])
    func volumeState(volume: Result<String?, NSError>, expected: BookmarkFailureRule.VolumeState) {
        let adapter = BookmarkAdapter(system: FakeBookmarkSystem(.init(volumePath: volume, existingPaths: ["/"])))

        #expect(adapter.volumeState(of: Data("bookmark".utf8)) == expected)
    }

    @Test("[W06-resolve-failure-end-to-end] 실제 해석 실패는 오류와 볼륨 상태를 함께 써서 원인을 정한다", arguments: [
        (NSFileNoSuchFileError, Result<String?, NSError>.success("/Volumes/분리됨"), BookmarkFailureCause.volumeUnavailable),
        (NSFileNoSuchFileError, .success("/"), .missing),
        (NSFileNoSuchFileError, .failure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)), .checkFailed),
        (NSFileReadNoPermissionError, .success("/"), .accessDenied),
    ])
    func resolveFailureEndToEnd(code: Int, volume: Result<String?, NSError>, expected: BookmarkFailureCause) {
        let adapter = BookmarkAdapter(system: FakeBookmarkSystem(.init(
            resolveError: NSError(domain: NSCocoaErrorDomain, code: code), volumePath: volume, existingPaths: ["/"]
        )))

        #expect(throws: BookmarkError.resolutionFailed(expected)) { try adapter.resolve(Data("bookmark".utf8)) }
    }

    @Test("[W06-resolve-failure-end-to-end] 보안 범위 해석의 오류가 불분명하면 범위 없는 해석의 오류로 원인을 정한다", arguments: [
        (Result<Void, NSError>.failure(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)), BookmarkFailureCause.missing),
        (.failure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)), .accessDenied),
        (.success(()), .checkFailed),
    ])
    func unscopedRetryClassifies(unscoped: Result<Void, NSError>, expected: BookmarkFailureCause) {
        // sandbox에서는 삭제된 대상의 보안 범위 해석이 형식 오류(259)로 실패하고, 범위 없는 해석은 파일 없음(4)으로 실패한다.
        let adapter = BookmarkAdapter(system: FakeBookmarkSystem(.init(
            resolveError: NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError),
            unscopedResolve: unscoped, volumePath: .success("/"), existingPaths: ["/"]
        )))

        #expect(throws: BookmarkError.resolutionFailed(expected)) { try adapter.resolve(Data("bookmark".utf8)) }
    }

    @Test("[W06-failure-cause-decision] 해석 실패 원인을 볼륨 상태와 오류 범주로 분류한다(R1~R5, 9조합)", arguments: [
        (BookmarkFailureRule.VolumeState.unmounted, BookmarkFailureRule.ErrorKind.noSuchFile, BookmarkFailureCause.volumeUnavailable),
        (.unmounted, .noPermission, .volumeUnavailable),
        (.unmounted, .other, .volumeUnavailable),
        (.mounted, .noPermission, .accessDenied),
        (.unknown, .noPermission, .accessDenied),
        (.mounted, .noSuchFile, .missing),
        (.unknown, .noSuchFile, .checkFailed),
        (.mounted, .other, .checkFailed),
        (.unknown, .other, .checkFailed),
    ])
    func failureCauseDecision(volume: BookmarkFailureRule.VolumeState, error: BookmarkFailureRule.ErrorKind, expected: BookmarkFailureCause) {
        #expect(BookmarkFailureRule.classify(volume: volume, error: error) == expected)
    }

    // MARK: 접근 범위

    struct WorkFailed: Error, Equatable {}

    @Test("[W06-scoped-access-pairing] 보안 범위 접근은 시작한 경우에만 정확히 한 번 끝낸다", arguments: [
        (true, false, 1), (true, true, 1), (false, false, 0), (false, true, 0),
    ])
    func scopedAccessPairing(startSucceeds: Bool, workThrows: Bool, expectedStops: Int) {
        let resource = FakeScopedResource(startSucceeds: startSucceeds)
        var runs = 0

        let result = Result { () throws(WorkFailed) -> Int in
            try adapter.withAccess(to: resource) { () throws(WorkFailed) -> Int in
                runs += 1
                if workThrows { throw WorkFailed() }
                return 42
            }
        }

        #expect(runs == 1)
        #expect(resource.starts == 1)
        #expect(resource.stops == expectedStops)
        #expect(result == (workThrows ? .failure(WorkFailed()) : .success(42)))
    }

    // MARK: 식별자

    @Test("[W06-identity-same-and-different] 같은 대상의 식별자는 같고, 다른 대상의 식별자는 다르다")
    func identitySameAndDifferent() throws {
        try withTemporaryDirectory { directory throws in
            let a = try makeFile(directory, "a.md")
            let b = try makeFile(directory, "b.md")
            _ = try makeFolder(directory, "sub")
            let link = directory.appending(path: "linked")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)

            let identityA = adapter.identity(of: a)
            let identityB = adapter.identity(of: b)

            #expect(identityA.file != nil && identityA.volume != nil)
            #expect(adapter.identity(of: link.appending(path: "a.md")) == identityA)
            #expect(adapter.identity(of: URL(filePath: directory.path + "/./sub/../a.md")) == identityA)
            #expect(identityA.file != identityB.file)
            #expect(identityA.volume == identityB.volume)
        }
    }

    @Test("[W06-identity-survives-rename] 같은 볼륨 안에서 이동·이름 변경한 대상은 같은 파일 식별자를 가진다")
    func identitySurvivesRename() throws {
        try withTemporaryDirectory { directory throws in
            let url = try makeFile(directory, "a.md")
            let before = adapter.identity(of: url)
            let renamed = directory.appending(path: "renamed.md")
            try FileManager.default.moveItem(at: url, to: renamed)

            #expect(TargetIdentityRule.identity(old: before, new: adapter.identity(of: renamed)) == .sameTarget)
        }
    }

    @Test("[W06-identity-missing] 없는 대상의 식별자는 얻을 수 없다")
    func identityOfMissingTarget() throws {
        try withTemporaryDirectory { directory throws in
            #expect(adapter.identity(of: directory.appending(path: "nothing.md")) == FileSystemIdentity(file: nil, volume: nil))
        }
    }

    // MARK: 원본 보존

    @Test("[W06-target-untouched] 북마크 생성·해석·접근·식별자 조회는 대상을 바꾸지 않는다", .tags(.A02))
    func targetIsUntouched() throws {
        try withTemporaryDirectory { directory throws in
            let file = try makeFile(directory, "design.md")
            let folder = try makeFolder(directory, "assets")
            _ = try makeFile(folder, "inner.png")
            let before = try fingerprint(file: file, folder: folder)

            for url in [file, folder] {
                let creation = try adapter.createBookmark(for: url)
                let resolution = try adapter.resolve(creation.bookmarkData)
                _ = adapter.withAccess(to: resolution.url) { FileManager.default.fileExists(atPath: resolution.url.path) }
                _ = adapter.identity(of: url)
            }

            #expect(try fingerprint(file: file, folder: folder) == before)
        }
    }

    // MARK: 도우미

    private func makeFile(_ directory: URL, _ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data("내용 \(name)".utf8).write(to: url)
        return url
    }

    private func makeFolder(_ directory: URL, _ name: String) throws -> URL {
        let url = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    struct Fingerprint: Equatable {
        var contents: Data
        var modified: Date?
        var permissions: Int?
        var listing: [String]
    }

    private func fingerprint(file: URL, folder: URL) throws -> Fingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        return Fingerprint(
            contents: try Data(contentsOf: file),
            modified: attributes[.modificationDate] as? Date,
            permissions: attributes[.posixPermissions] as? Int,
            listing: try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        )
    }
}
