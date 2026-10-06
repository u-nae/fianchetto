import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import Fianchetto

/// 화면 스냅샷(0028): 디자인 부품의 회귀를 기준 이미지와 비교해 잡는다.
/// 기준 이미지는 개발 기기(macOS 27)·2배율·한국어·라이트/다크 고정으로 기록했다. macOS 15 화면 확인을 대신하지 않는다.
/// NSView cacheDisplay 계열은 compositingGroup·blendMode 합성을 무시하므로, SwiftUI ImageRenderer로 그린다.
@MainActor
enum SnapshotSupport {
    static let perceptualPrecision: Float = 0.98

    /// 창 배경 위에 view를 그린 2배율 이미지.
    static func render<Content: View>(_ content: Content, scheme: ColorScheme) -> NSImage {
        let framed = content
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "ko_KR"))
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        // 동적 NSColor(창 배경, 글자색)를 그 외형으로 풀어 그리게 한다.
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        var image: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            image = renderer.nsImage
        }
        return image ?? NSImage()
    }

    /// 라이트·다크 두 장을 기준 이미지와 비교한다.
    /// 단위 테스트 호스트 앱은 샌드박스라 저장소에 쓰거나 읽을 수 없다. 기준 이미지는 테스트 번들 리소스로 들어오고,
    /// 비교는 앱 임시 폴더에서 한다. 기준 이미지가 없으면 그 폴더에 새로 기록하고 실패한다
    /// (scripts/record-snapshots.sh가 저장소의 FianchettoTests/Snapshots/References로 옮긴다).
    static func assertMatches<Content: View>(
        _ content: Content, named name: String,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let suite = URL(fileURLWithPath: "\(file)").deletingPathExtension().lastPathComponent
        let directory = workDirectory.appending(path: suite)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let identifier = "\(name)-\(scheme == .dark ? "dark" : "light")"
            let fileName = "\(sanitized(testName)).\(identifier).png"
            let target = directory.appending(path: fileName)
            try? FileManager.default.removeItem(at: target)
            if let reference = Bundle(for: BundleToken.self).url(forResource: fileName, withExtension: nil) {
                try? FileManager.default.copyItem(at: reference, to: target)
            }
            let failure = verifySnapshot(
                of: render(content, scheme: scheme),
                as: .image(precision: 1, perceptualPrecision: perceptualPrecision),
                named: identifier, record: .missing, snapshotDirectory: directory.path,
                file: file, testName: testName, line: line
            )
            if let failure { Issue.record(Comment(rawValue: failure)) }
        }
    }

    /// 앱 컨테이너 임시 폴더 아래 스냅샷 작업 폴더. 기록 스크립트가 여기서 새 이미지를 가져간다.
    static var workDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "FianchettoSnapshots")
    }

    /// swift-snapshot-testing이 파일 이름에 쓰는 테스트 이름 정리(영숫자 외 문자를 '-'로, 앞뒤 '-' 제거).
    private static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
    }
}

/// 테스트 번들을 찾기 위한 표식.
private final class BundleToken {}
