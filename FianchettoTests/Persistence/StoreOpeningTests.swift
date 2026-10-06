import Foundation
import SwiftData
import Testing
@testable import Fianchetto

@Suite("저장소 열기와 스키마 (W04)")
struct StoreOpeningTests {
    typealias R = RecordFixtures

    @Test("[W04-open-creates-missing-store] 저장소 파일이 없으면 새 저장소를 만든다")
    func missingStoreIsCreated() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                let projects = try store.projects()
                #expect(projects.isEmpty)
            }
        }
    }

    @Test("[W04-open-creates-directory] 저장소 디렉토리가 없으면 만들고 연다")
    func missingDirectoryIsCreated() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto/Fianchetto.store")

            try withStore(at: url) { store throws in
                let projects = try store.projects()
                #expect(projects.isEmpty)
            }
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Fianchetto").path))
        }
    }

    enum BrokenState: String, CaseIterable, Sendable {
        // 앱보다 새로운 스키마 저장소(incompatible)는 테스트 전용 V2 스키마가 필요해 SchemaMigrationTests에서 따로 본다(0031).
        case garbage, garbageWithWAL, zeroBytes, auxiliaryFilesOnly, unreadable
    }

    @Test("[W04-open-failure-preserves-store] 기존 저장소를 열 수 없으면 원인 범주가 담긴 오류를 돌려주고 파일을 바꾸지 않는다",
          arguments: BrokenState.allCases)
    func unopenableStoreIsPreserved(state: BrokenState) throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            let expected: StoreOpenError.Category
            switch state {
            case .garbage:
                try Data("not a store".utf8).write(to: url)
                expected = .damaged
            case .garbageWithWAL:
                try Data("not a store".utf8).write(to: url)
                try Data(repeating: 0x5A, count: 4096).write(to: URL(filePath: url.path + "-wal"))
                expected = .damaged
            case .zeroBytes:
                try Data().write(to: url)
                expected = .damaged
            case .auxiliaryFilesOnly:
                try Data(repeating: 0x5A, count: 4096).write(to: URL(filePath: url.path + "-wal"))
                try Data(repeating: 0x00, count: 32768).write(to: URL(filePath: url.path + "-shm"))
                expected = .damaged
            case .unreadable:
                let seed = directory.appending(path: "seed/Fianchetto.store")
                try withStore(at: seed, seedBasicRecords)
                try copyStoreFiles(from: seed, to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
                expected = .accessDenied
            }
            let before = storeFileBytesIgnoringPermissions(url)

            #expect(throws: StoreOpenError(category: expected, url: url)) { try StoreOpener.open(at: url) }

            #expect(storeFileBytesIgnoringPermissions(url) == before)
        }
    }

    @Test("[W04-default-store-location] 기본 저장소 위치는 앱의 Application Support 아래다")
    func defaultLocation() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

        let url = try StoreOpener.defaultStoreURL()

        #expect(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == support.standardizedFileURL)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Fianchetto")
        #expect(url.lastPathComponent == "Fianchetto.store")
    }

    @Test("[W04-schema-v1-declared] 앱의 스키마 버전 목록은 V1에서 시작하고 이전 계획이 그 목록을 따른다", .tags(.A18))
    func schemaV1IsDeclared() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        let names = Set(SchemaV1.models.map { String(describing: $0) })
        #expect(names == ["ProjectModel", "RevisionModel", "ResourceReferenceModel", "CheckpointModel", "AttachmentModel"])
        #expect(!names.contains { $0.contains("Node") })
        #expect(FianchettoMigrationPlan.schemas.count == 1)
        #expect(FianchettoMigrationPlan.schemas.first == SchemaV1.self)
        #expect(FianchettoMigrationPlan.stages.isEmpty)
    }

    // MARK: 도우미

    /// 권한이 없는 파일도 비교할 수 있게 잠시 읽기 권한을 주고 바이트를 읽은 뒤 원래 권한으로 되돌린다.
    private func storeFileBytesIgnoringPermissions(_ url: URL) -> [String: Data?] {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes?[.posixPermissions]
        if permissions != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        defer {
            if let permissions {
                try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
            }
        }
        return storeFileBytes(url)
    }
}
