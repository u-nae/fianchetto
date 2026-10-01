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
        case garbage, garbageWithWAL, zeroBytes, auxiliaryFilesOnly, newerSchema, unreadable
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
            case .newerSchema:
                let seed = directory.appending(path: "seed/Fianchetto.store")
                try createNewerSchemaStore(at: seed)
                try copyStoreFiles(from: seed, to: url)
                expected = .incompatible
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

    @Test("[W04-migration-preserves-v1-data] 스키마 V1에서 만든 데이터는 다음 스키마 버전으로 이전한 뒤에도 유지된다", .tags(.A18))
    func migrationPreservesV1Data() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            try withStore(at: url, seedBasicRecords)

            let container = try StoreOpener.open(at: url, migrationPlan: TestMigrationPlanV2.self)
            let context = ModelContext(container)

            let revisions = try context.fetch(FetchDescriptor<TestSchemaV2.RevisionModel>(sortBy: [SortDescriptor(\.sequence)]))
            #expect(revisions.map(\.id) == [R.r1, R.r2])
            #expect(revisions.map(\.cause) == ["created", "renameNode"])
            #expect(revisions.allSatisfy { $0.note == nil })
            let expected = SnapshotFixtures.serviceA().updating(SnapshotFixtures.backend) { $0.displayName = "api" }
            #expect(try SnapshotCodec.decode(revisions[1].snapshotData) == expected)
            let store = StoreAdapter(context: context)
            #expect(try store.project(R.project) == R.projectRecord())
            #expect(try store.reference(R.backendReference.id) == R.backendReference)
            let checkpoints = try context.fetch(FetchDescriptor<SchemaV1.CheckpointModel>())
            #expect(checkpoints.map(\.id) == [R.c1])
            #expect(checkpoints.first?.title == R.checkpoint().title)
        }
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

    /// fixture를 만든 연결이 같은 프로세스에 살아 있으면 보조 파일이 계속 바뀐다.
    /// 그래서 다른 위치에서 만든 저장소 파일 묶음을 복사해, 열린 연결이 없는 저장소로 검사한다.
    private func copyStoreFiles(from source: URL, to destination: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(filePath: source.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: file, to: URL(filePath: destination.path + suffix))
            }
        }
    }

    private func createNewerSchemaStore(at url: URL) throws {
        let container = try StoreOpener.open(at: url, migrationPlan: TestNewerOnlyPlan.self)
        let context = ModelContext(container)
        context.insert(TestSchemaV2.RevisionModel(
            id: R.r1, projectID: R.project, sequence: 1, recordedAt: date(0),
            cause: "created", projectName: "서비스 A", snapshotData: Data("{}".utf8)
        ))
        try context.save()
    }

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
