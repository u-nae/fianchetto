import Foundation
import Testing
@testable import Fianchetto

/// 결정표 node_shape_validity(W02.decision.yaml)의 규칙별 대표 입력.
@Suite("Node 종류별 필드 모양 결정표 (W02)")
struct NodeShapeRuleTests {
    typealias Rule = NodeShapeRule

    struct Row: Sendable, CustomTestStringConvertible {
        var ruleID: String
        var parent: Rule.ParentKind
        var kind: NodeKind
        var reference: Rule.ReferenceFields
        var url: Rule.URLShape
        var expected: SnapshotViolationKind?
        var testDescription: String { ruleID }
    }

    static let parentRules: [Row] = [
        Row(ruleID: "R1", parent: .file, kind: .file, reference: .complete, url: .absent, expected: .parentNotGroup),
        Row(ruleID: "R2", parent: .folder, kind: .group, reference: .none, url: .absent, expected: .parentNotGroup),
        Row(ruleID: "R3", parent: .webLink, kind: .webLink, reference: .none, url: .httpOrHTTPS, expected: .parentNotGroup),
    ]

    static let shapeRules: [Row] = [
        Row(ruleID: "R4", parent: .root, kind: .group, reference: .complete, url: .httpOrHTTPS, expected: .unexpectedReference),
        Row(ruleID: "R5", parent: .group, kind: .group, reference: .incomplete, url: .absent, expected: .unexpectedReference),
        Row(ruleID: "R6", parent: .root, kind: .group, reference: .none, url: .httpOrHTTPS, expected: .unexpectedURL),
        Row(ruleID: "R7", parent: .root, kind: .group, reference: .none, url: .other, expected: .unexpectedURL),
        Row(ruleID: "R8", parent: .group, kind: .group, reference: .none, url: .absent, expected: nil),
        Row(ruleID: "R9", parent: .root, kind: .file, reference: .none, url: .httpOrHTTPS, expected: .missingReference),
        Row(ruleID: "R10", parent: .group, kind: .folder, reference: .none, url: .absent, expected: .missingReference),
        Row(ruleID: "R11", parent: .root, kind: .file, reference: .incomplete, url: .other, expected: .incompleteReference),
        Row(ruleID: "R12", parent: .root, kind: .folder, reference: .incomplete, url: .absent, expected: .incompleteReference),
        Row(ruleID: "R13", parent: .root, kind: .file, reference: .complete, url: .httpOrHTTPS, expected: .unexpectedURL),
        Row(ruleID: "R14", parent: .group, kind: .file, reference: .complete, url: .other, expected: .unexpectedURL),
        Row(ruleID: "R15", parent: .root, kind: .folder, reference: .complete, url: .httpOrHTTPS, expected: .unexpectedURL),
        Row(ruleID: "R16", parent: .root, kind: .folder, reference: .complete, url: .other, expected: .unexpectedURL),
        Row(ruleID: "R17", parent: .group, kind: .file, reference: .complete, url: .absent, expected: nil),
        Row(ruleID: "R18", parent: .root, kind: .folder, reference: .complete, url: .absent, expected: nil),
        Row(ruleID: "R19", parent: .root, kind: .webLink, reference: .complete, url: .httpOrHTTPS, expected: .unexpectedReference),
        Row(ruleID: "R20", parent: .root, kind: .webLink, reference: .incomplete, url: .absent, expected: .unexpectedReference),
        Row(ruleID: "R21", parent: .group, kind: .webLink, reference: .none, url: .absent, expected: .missingURL),
        Row(ruleID: "R22", parent: .root, kind: .webLink, reference: .none, url: .other, expected: .invalidURL),
        Row(ruleID: "R23", parent: .root, kind: .webLink, reference: .none, url: .httpOrHTTPS, expected: nil),
    ]

    @Test("[W02-parent-must-be-group] 부모는 그룹이거나 최상위여야 한다(R1~R3)", arguments: parentRules)
    func parentMustBeGroup(row: Row) {
        #expect(Rule.evaluate(parent: row.parent, kind: row.kind, reference: row.reference, url: row.url) == row.expected)
    }

    @Test("[W02-node-shape-by-kind] Node 종류별 필드 모양을 결정표대로 판정한다(R4~R23)", arguments: shapeRules)
    func nodeShapeByKind(row: Row) {
        #expect(Rule.evaluate(parent: row.parent, kind: row.kind, reference: row.reference, url: row.url) == row.expected)
    }

    @Test("[W02-parent-must-be-group] 부모 위반은 Node 자체 필드보다 먼저 판정한다(FIRST)")
    func parentRuleTakesPrecedence() {
        #expect(Rule.evaluate(parent: .folder, kind: .webLink, reference: .complete, url: .other) == .parentNotGroup)
    }

    @Test("[W02-node-shape-by-kind] URL 모양 분류", arguments: [
        ("https://example.com/api", Rule.URLShape.httpOrHTTPS),
        ("HTTP://Example.com", .httpOrHTTPS),
        ("ftp://example.com", .other),
        ("example.com", .other),
        ("https:///path", .other),
        ("", .other),
    ])
    func urlShape(input: String, expected: Rule.URLShape) {
        #expect(Rule.urlShape(input) == expected)
    }

    @Test("[W02-node-shape-by-kind] URL이 없으면 absent다")
    func absentURL() {
        #expect(Rule.urlShape(nil) == .absent)
    }

    @Test("[W02-recorded-path-must-be-absolute] 참조 필드 모양 분류", arguments: [
        (fixedID(1) as UUID?, "/dev/legacy-api" as String?, Rule.ReferenceFields.complete),
        (nil, nil, .none),
        (fixedID(1), nil, .incomplete),
        (nil, "/dev/legacy-api", .incomplete),
        (fixedID(1), "", .incomplete),
        (fixedID(1), "dev/legacy-api", .incomplete),
    ])
    func referenceFields(reference: UUID?, path: String?, expected: Rule.ReferenceFields) {
        #expect(Rule.referenceFields(referenceID: reference, recordedPath: path) == expected)
    }
}
