import Foundation

enum SnapshotDecodingError: Error, Equatable, Sendable {
    /// schema version이 없거나(nil) 지원하지 않는 값이다.
    case unsupportedSchemaVersion(Int?)
    /// JSON이 손상되었거나 필수 필드·종류·UUID 형식이 맞지 않는다.
    case malformed
}

/// 구성 스냅샷 JSON의 기록과 읽기. 쓰기는 현재 버전(2), 읽기는 1·2를 받는다.
/// 버전 2는 Node 용도(purpose, 0021)를 더했다. 버전 1에는 용도가 없으므로 그대로 읽으면 용도 없음이다.
/// 더 새 버전은 값을 조용히 잃지 않도록 거부한다.
enum SnapshotCodec {
    static let currentSchemaVersion = 2
    static let readableSchemaVersions: Set<Int> = [1, 2]

    private struct Envelope: Codable {
        var schemaVersion: Int
        var projectName: String
        var nodes: [ConfigurationNode]
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
    }

    static func encode(_ snapshot: ConfigurationSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            Envelope(schemaVersion: currentSchemaVersion, projectName: snapshot.projectName, nodes: snapshot.nodes)
        )
    }

    static func decode(_ data: Data) throws(SnapshotDecodingError) -> ConfigurationSnapshot {
        let decoder = JSONDecoder()
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch {
            throw .malformed
        }
        guard let version = probe.schemaVersion, readableSchemaVersions.contains(version) else {
            throw .unsupportedSchemaVersion(probe.schemaVersion)
        }
        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            return ConfigurationSnapshot(projectName: envelope.projectName, nodes: envelope.nodes)
        } catch {
            throw .malformed
        }
    }
}
