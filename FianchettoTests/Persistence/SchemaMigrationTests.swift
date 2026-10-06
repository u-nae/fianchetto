import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 스키마 이전 테스트를 켜는 별도 실행인지. verify.sh는 `TEST_RUNNER_` 접두어를 붙여 이 값을 테스트 호스트에 넘긴다.
enum SchemaMigrationRun {
    static let environmentKey = "FIANCHETTO_SCHEMA_MIGRATION_TESTS"
    static var isIsolated: Bool { ProcessInfo.processInfo.environment[environmentKey] == "1" }
}

/// 테스트 전용 다음 스키마(TestSchemaV2)를 쓰는 테스트. V2의 RevisionModel은 앱 V1과 엔티티 이름이 같아서, 같은 프로세스에서
/// V1 저장소 테스트와 동시에 돌면 SwiftData가 V1 저장에 V2 정의('note')를 써서 테스트 호스트가 종료된다(0031).
/// 그래서 평소 실행에서는 끄고, scripts/verify.sh가 이 묶음만 켠 별도 실행(별도 프로세스)에서 차례로 돌린다.
@Suite(
    "스키마 이전 (W04, 별도 실행)",
    .serialized,
    .enabled(if: SchemaMigrationRun.isIsolated, "V1 저장소 테스트와 한 프로세스에서 섞이지 않게 scripts/verify.sh의 별도 실행에서만 돈다(0031)")
)
struct SchemaMigrationTests {
    typealias R = RecordFixtures

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

    @Test("[W04-open-failure-preserves-store] 앱보다 새로운 스키마의 저장소는 호환되지 않음 오류를 돌려주고 파일을 바꾸지 않는다")
    func newerSchemaStoreIsPreserved() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            let seed = directory.appending(path: "seed/Fianchetto.store")
            try createNewerSchemaStore(at: seed)
            try copyStoreFiles(from: seed, to: url)
            let before = storeFileBytes(url)

            #expect(throws: StoreOpenError(category: .incompatible, url: url)) { try StoreOpener.open(at: url) }

            #expect(storeFileBytes(url) == before)
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
}
