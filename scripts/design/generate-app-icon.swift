// 앱 아이콘(시안 C: 대각선 면 분할)의 AppIcon.appiconset을 만든다.
// 월넛·아이보리 면을 긴 대각선으로 나누고, 미트라는 양쪽에서 색이 뒤바뀐다. 글자는 넣지 않는다.
// 색 값은 Assets.xcassets의 ThemeSurface·AccentColor 라이트 값과 같다(0011).
// 사용: swift scripts/design/generate-app-icon.swift Fianchetto/Assets.xcassets
import AppKit

func srgb(_ hex: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let walnut = srgb(0x8A5A2E)
let ivory = srgb(0xF6F1E7)

// 1024 캔버스, macOS 아이콘 격자: 본체 824×824, 여백 100, 모서리 반경 185.
let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Bishop 심볼(0013)과 같은 미트라를 채운 모양으로 그린다. 24 격자(y 아래 방향)를 캔버스(y 위 방향)로 옮긴다.
func mitre() -> CGPath {
    let unit: CGFloat = 26
    let t = CGAffineTransform(a: unit, b: 0, c: 0, d: -unit, tx: 512 - 12 * unit, ty: 512 + 11.5 * unit)
    let ball = CGMutablePath()
    ball.addEllipse(in: CGRect(x: 10.4, y: 1.4, width: 3.2, height: 3.2), transform: t)
    let crown = CGMutablePath()
    crown.move(to: CGPoint(x: 12, y: 5.6), transform: t)
    crown.addCurve(to: CGPoint(x: 16.2, y: 17.6), control1: CGPoint(x: 17.8, y: 8.8), control2: CGPoint(x: 18.9, y: 14.2), transform: t)
    crown.addLine(to: CGPoint(x: 7.8, y: 17.6), transform: t)
    crown.addCurve(to: CGPoint(x: 12, y: 5.6), control1: CGPoint(x: 5.1, y: 14.2), control2: CGPoint(x: 6.2, y: 8.8), transform: t)
    crown.closeSubpath()
    let slit = CGMutablePath()
    slit.move(to: CGPoint(x: 16.5, y: 8.0), transform: t)
    slit.addLine(to: CGPoint(x: 10.2, y: 14.4), transform: t)
    let cut = slit.copy(strokingWithWidth: 1.5 * unit, lineCap: .butt, lineJoin: .round, miterLimit: 10)
    let base = CGMutablePath()
    base.addRoundedRect(in: CGRect(x: 6.6, y: 18.6, width: 10.8, height: 3), cornerWidth: 1.2, cornerHeight: 1.2, transform: t)
    return ball.union(crown.subtracting(cut)).union(base)
}

func draw(in c: CGContext) {
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
    c.setFillColor(ivory)
    c.addPath(shape)
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(shape)
    c.clip()
    // 왼쪽 위 삼각형(월넛)과 오른쪽 아래(아이보리)를 긴 대각선으로 나눈다.
    let upperLeft = CGMutablePath()
    upperLeft.move(to: .zero)
    upperLeft.addLine(to: CGPoint(x: canvas, y: canvas))
    upperLeft.addLine(to: CGPoint(x: 0, y: canvas))
    upperLeft.closeSubpath()
    c.setFillColor(walnut)
    c.addPath(upperLeft)
    c.fillPath()

    let piece = mitre()
    c.saveGState()
    c.addPath(upperLeft)
    c.clip()
    c.setFillColor(ivory)
    c.addPath(piece)
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addRect(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    c.addPath(upperLeft)
    c.clip(using: .evenOdd)
    c.setFillColor(walnut)
    c.addPath(piece)
    c.fillPath()
    c.restoreGState()

    c.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
    c.setLineWidth(3)
    c.addPath(shape)
    c.strokePath()
    c.restoreGState()
}

func png(pixels: Int) throws -> Data {
    guard let c = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.featureUnsupported) }
    c.interpolationQuality = .high
    c.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    draw(in: c)
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.featureUnsupported) }
    return data
}

let set = "\(CommandLine.arguments[1])/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
var entries: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: size * scale).write(to: URL(fileURLWithPath: "\(set)/\(name)"))
        entries.append("""
            {
              "filename" : "\(name)",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(size)x\(size)"
            }
        """)
    }
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(toFile: "\(set)/Contents.json", atomically: true, encoding: .utf8)
