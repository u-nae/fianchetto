import Foundation
import SwiftUI
import Testing
@testable import Fianchetto

/// Bishop 타일·배지(DESIGN 17.3·18장, 0022): 용도 8종 + 기본, 폴더 Bishop(F1), 파일 종류 아이콘 모드.
@MainActor
@Suite("스냅샷: Bishop 타일·배지(0028)")
struct TileIconSnapshotTests {
    private static func node(_ kind: NodeKind, purpose: BishopPurpose? = nil, path: String = "/a/doc.md") -> ConfigurationNode {
        ConfigurationNode(
            id: fixedID(1), kind: kind, displayName: "item", parentID: nil, sortIndex: 0,
            referenceID: fixedID(2), recordedPath: path, purpose: purpose?.rawValue
        )
    }

    /// 한 줄: 기본 + 용도 8종(파일 Bishop). 둘째 줄: 폴더(용도 없음), 폴더(용도 있음, F1), Wing, 웹 링크.
    /// 셋째 줄: 파일 종류 아이콘 모드의 파일(.md, .pages, 확장자 없음)과 폴더.
    private static func grid(size: CGFloat) -> some View {
        let purposes: [BishopPurpose?] = [nil] + BishopPurpose.allCases.map(Optional.some)
        return VStack(alignment: .leading, spacing: size / 2) {
            HStack(spacing: size / 2) {
                ForEach(Array(purposes.enumerated()), id: \.offset) { _, purpose in
                    TileIconView(icon: TileIcon.of(node(.file, purpose: purpose), style: .symbol), size: size)
                }
            }
            HStack(spacing: size / 2) {
                TileIconView(icon: TileIcon.of(node(.folder), style: .symbol), size: size)
                TileIconView(icon: TileIcon.of(node(.folder, purpose: .code), style: .symbol), size: size)
                TileIconView(icon: .wing, size: size)
                TileIconView(icon: .systemSymbol("link"), size: size)
            }
            HStack(spacing: size / 2) {
                TileIconView(icon: TileIcon.of(node(.file, path: "/a/doc.md"), style: .fileType), size: size)
                TileIconView(icon: TileIcon.of(node(.file, path: "/a/deck.pages"), style: .fileType), size: size)
                TileIconView(icon: TileIcon.of(node(.file, path: "/a/README"), style: .fileType), size: size)
                TileIconView(icon: TileIcon.of(node(.folder), style: .fileType), size: size)
            }
        }
        .foregroundStyle(Color.accentColor)
    }

    @Test("[0028] 아이콘 보기 크기(40pt)의 타일·배지가 기준 이미지와 같다")
    func icons40() {
        SnapshotSupport.assertMatches(Self.grid(size: 40), named: "tiles-40")
    }

    @Test("[0028] 목록 크기(16pt)의 타일·배지가 기준 이미지와 같다")
    func icons16() {
        SnapshotSupport.assertMatches(Self.grid(size: 16), named: "tiles-16")
    }
}
