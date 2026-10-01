import Foundation
import Testing
@testable import Fianchetto

@Suite("구성 스냅샷 직렬화 (W02)")
struct SnapshotCodingTests {
    @Test("[W02-json-roundtrip] 유효한 스냅샷은 JSON으로 기록한 뒤 다시 읽어도 같은 구성이다")
    func roundTripPreservesConfiguration() throws {
        let snapshot = SnapshotFixtures.serviceA()

        let decoded = try SnapshotCodec.decode(SnapshotCodec.encode(snapshot))

        #expect(decoded == snapshot)
        let original = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        for node in decoded.nodes {
            let expected = try #require(original[node.id])
            #expect(node.displayName == expected.displayName)
            #expect(node.kind == expected.kind)
            #expect(node.parentID == expected.parentID)
            #expect(node.sortIndex == expected.sortIndex)
            #expect(node.referenceID == expected.referenceID)
            #expect(node.recordedPath == expected.recordedPath)
            #expect(node.url == expected.url)
        }
        #expect(decoded.projectName == "서비스 A")
    }

    @Test("[W02-schema-version-recorded] 기록한 JSON에는 스냅샷 schema version 1이 담긴다")
    func encodedJSONCarriesSchemaVersion() throws {
        let data = try SnapshotCodec.encode(SnapshotFixtures.serviceA())

        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(SnapshotCodec.currentSchemaVersion == 1)
    }

    @Test("[W02-unsupported-schema-version-rejected] 지원하지 않는 schema version의 JSON은 읽지 않는다", arguments: [
        (#"{"schemaVersion":0,"projectName":"서비스 A","nodes":[]}"#, 0 as Int?),
        (#"{"schemaVersion":2,"projectName":"서비스 A","nodes":[]}"#, 2 as Int?),
        (#"{"projectName":"서비스 A","nodes":[]}"#, nil as Int?),
    ])
    func unsupportedSchemaVersionIsRejected(json: String, version: Int?) {
        #expect(throws: SnapshotDecodingError.unsupportedSchemaVersion(version)) {
            try SnapshotCodec.decode(Data(json.utf8))
        }
    }

    @Test("[W02-corrupt-json-rejected] 손상된 JSON은 읽지 않는다", arguments: [
        #"{"schemaVersion":1,"projectName":"서비스 A","nodes":[{"id":"#,
        #"{"schemaVersion":1,"projectName":"서비스 A","nodes":[{"id":"00000000-0000-0000-0000-000000000001","kind":"symlink","displayName":"x","sortIndex":0}]}"#,
        #"{"schemaVersion":1,"projectName":"서비스 A","nodes":[{"id":"not-a-uuid","kind":"group","displayName":"x","sortIndex":0}]}"#,
        #"{"schemaVersion":1,"projectName":"서비스 A","nodes":[{"id":"00000000-0000-0000-0000-000000000001","kind":"group","sortIndex":0}]}"#,
        #"{"schemaVersion":1,"projectName":"서비스 A","nodes":[{"id":"00000000-0000-0000-0000-000000000001","kind":"group","displayName":"x"}]}"#,
        #"{"schemaVersion":1,"nodes":[]}"#,
    ])
    func corruptJSONIsRejected(json: String) {
        #expect(throws: SnapshotDecodingError.malformed) {
            try SnapshotCodec.decode(Data(json.utf8))
        }
    }
}
