import Foundation
import Testing

/// 테스트 임시 디렉토리 도우미가 만든 것을 남김없이 지우는지 확인한다(테스트가 만든 파일은 테스트가 정리한다).
/// 하위 폴더에 실행 권한이 빠지면 안의 항목을 지우지 못해, 실행마다 폴더가 앱 컨테이너 tmp에 쌓였다.
@Suite("테스트 임시 디렉토리 정리")
struct TemporaryDirectoryTests {
    private let fileManager = FileManager.default

    /// 하위 폴더, 권한을 막은 파일, 권한을 막은 폴더(안에 파일 포함)를 만든다.
    private func fillWithLockedItems(_ directory: URL) throws {
        let nested = directory.appending(path: "browser/inner")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: nested.appending(path: "Fianchetto.store"))
        let sealedFile = directory.appending(path: "browser/sealed")
        try Data("x".utf8).write(to: sealedFile)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sealedFile.path)
        let lockedFolder = directory.appending(path: "targets/locked")
        try fileManager.createDirectory(at: lockedFolder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: lockedFolder.appending(path: "v2"))
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedFolder.path)
    }

    @Test("하위 폴더와 권한을 막은 항목이 있어도 본문이 끝나면 임시 디렉토리를 지운다")
    func removesNestedAndLockedItems() throws {
        var created: URL?
        try withTemporaryDirectory { directory in
            created = directory
            try fillWithLockedItems(directory)
        }
        let directory = try #require(created)
        #expect(!fileManager.fileExists(atPath: directory.path))
    }

    @Test("비동기 도우미도 하위 폴더와 권한을 막은 항목까지 지운다")
    func asyncRemovesNestedAndLockedItems() async throws {
        var created: URL?
        try await withTemporaryDirectoryAsync { directory in
            created = directory
            try fillWithLockedItems(directory)
        }
        let directory = try #require(created)
        #expect(!fileManager.fileExists(atPath: directory.path))
    }

    @Test("본문이 오류를 던져도 임시 디렉토리를 지운다")
    func removesWhenBodyThrows() throws {
        struct Failure: Error {}
        var created: URL?
        #expect(throws: Failure.self) {
            try withTemporaryDirectory { directory in
                created = directory
                try fillWithLockedItems(directory)
                throw Failure()
            }
        }
        let directory = try #require(created)
        #expect(!fileManager.fileExists(atPath: directory.path))
    }

    @Test("임시 디렉토리 안의 심볼릭 링크가 가리키는 바깥 항목은 권한도 내용도 바꾸지 않는다")
    func leavesSymlinkTargetsOutside() throws {
        try withTemporaryDirectory { outside in
            let target = outside.appending(path: "original")
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: target.appending(path: "keep"))
            try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: target.path)
            defer { try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path) }

            try withTemporaryDirectory { directory in
                try fileManager.createSymbolicLink(at: directory.appending(path: "link"), withDestinationURL: target)
            }

            let permissions = try fileManager.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
            #expect(permissions == 0o500)
            #expect(fileManager.fileExists(atPath: target.appending(path: "keep").path))
        }
    }
}
