import CoreData
import Foundation
import OSLog
import SwiftData

struct StoreOpenError: Error, Equatable, Sendable {
    enum Category: Sendable {
        /// 저장소 파일을 읽을 권한이 없다.
        case accessDenied
        /// 저장소 파일 형식이 아니거나, 본 파일 없이 보조 파일만 있다.
        case damaged
        /// 저장소 메타데이터가 앱의 어떤 스키마 버전과도 맞지 않는다(주로 더 새로운 앱이 만든 저장소).
        case incompatible
        /// 그 밖의 이유로 열지 못했다.
        case unavailable
    }

    var category: Category
    var url: URL
}

/// 저장소를 연다. 파일이 없으면 새로 만들고, 파일이 있는데 열 수 없으면 오류를 돌려주며 기존 파일을 바꾸지 않는다(PRD §7).
enum StoreOpener {
    private static let logger = AppLog.logger(.persistence)
    private static let sqliteHeader = Data("SQLite format 3\u{0}".utf8)

    static func defaultStoreURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appending(path: "Fianchetto/Fianchetto.store")
    }

    static func open(
        at url: URL,
        migrationPlan plan: any SchemaMigrationPlan.Type = FianchettoMigrationPlan.self
    ) throws(StoreOpenError) -> ModelContainer {
        func fail(_ category: StoreOpenError.Category) -> StoreOpenError {
            logger.error("Store open failed: \(String(describing: category), privacy: .public) at \(url.path, privacy: .private)")
            return StoreOpenError(category: category, url: url)
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw fail(.unavailable)
        }

        let files = storeFiles(url)
        let mainExists = fileManager.fileExists(atPath: url.path)
        if mainExists {
            guard fileManager.isReadableFile(atPath: url.path) else { throw fail(.accessDenied) }
            guard hasSQLiteHeader(url) else { throw fail(.damaged) }
        } else if files.dropFirst().contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            throw fail(.damaged)
        }
        guard let latest = plan.schemas.last else { throw fail(.unavailable) }

        // 검사나 열기 시도가 기존 파일을 바꾸더라도 실패하면 원래 바이트로 되돌린다.
        let backup: StoreBackup?
        do {
            backup = mainExists ? try StoreBackup(files: files) : nil
        } catch {
            throw fail(.unavailable)
        }
        // SwiftData는 계획에 없는 스키마의 저장소도 열면서 현재 스키마로 바꿀 수 있다(새 버전 앱의 데이터 훼손).
        // 그래서 열기 전에 저장소가 계획의 스키마 중 하나와 맞는지 확인한다.
        if mainExists, isIncompatible(url, plan: plan) {
            backup?.restore()
            throw fail(.incompatible)
        }
        do {
            let schema = Schema(versionedSchema: latest)
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: plan, configurations: [configuration])
            backup?.discard()
            return container
        } catch {
            backup?.restore()
            throw fail(.unavailable)
        }
    }

    /// 저장소 파일과 -wal·-shm 보조 파일.
    private static func storeFiles(_ url: URL) -> [URL] {
        [url, URL(filePath: url.path + "-wal"), URL(filePath: url.path + "-shm")]
    }

    private static func hasSQLiteHeader(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: sqliteHeader.count)) == sqliteHeader
    }

    /// 저장소 메타데이터가 계획의 어떤 스키마 버전과도 맞지 않으면 true. 메타데이터를 읽지 못하면 판정하지 않는다(false).
    private static func isIncompatible(_ url: URL, plan: any SchemaMigrationPlan.Type) -> Bool {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url) else {
            return false
        }
        return !plan.schemas.contains { versioned in
            NSManagedObjectModel.makeManagedObjectModel(for: versioned.models)?
                .isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) == true
        }
    }
}

/// 열기 전에 저장소 파일 묶음을 임시 위치에 복사해 두고, 실패하면 원래 상태로 되돌린다.
private struct StoreBackup {
    private let directory: URL
    private let entries: [(original: URL, copy: URL?)]

    init(files: [URL]) throws {
        let fileManager = FileManager.default
        directory = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: files[0], create: true
        )
        var entries: [(URL, URL?)] = []
        for (index, file) in files.enumerated() {
            if fileManager.fileExists(atPath: file.path) {
                let copy = directory.appending(path: "\(index)")
                try fileManager.copyItem(at: file, to: copy)
                entries.append((file, copy))
            } else {
                entries.append((file, nil))
            }
        }
        self.entries = entries
    }

    func restore() {
        let fileManager = FileManager.default
        for (original, copy) in entries {
            try? fileManager.removeItem(at: original)
            if let copy {
                try? fileManager.copyItem(at: copy, to: original)
            }
        }
        discard()
    }

    func discard() {
        try? FileManager.default.removeItem(at: directory)
    }
}
