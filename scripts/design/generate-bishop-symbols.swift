// Bishop 커스텀 심볼(0013)의 SF Symbols 템플릿을 만든다.
// 24 격자의 선 디자인을 채운 윤곽선으로 바꿔 Regular 굵기의 S·M·L 세 크기를 담는다(굵기 보간 없음).
// 크기마다 글리프가 있어야 `.imageScale(.small/.large)`(툴바는 .large)에서 비지 않는다.
// 사용: swift scripts/design/generate-bishop-symbols.swift Fianchetto/Assets.xcassets
// CGPath 불리언 연산을 쓰므로 macOS 14 이상에서 실행한다. 앱 실행 환경과는 무관하다.
import CoreGraphics
import Foundation

// 24-grid design (y down), stroked at SW and converted to filled outlines.
let SW: CGFloat = 1.6

func mitreParts(_ t: CGAffineTransform) -> [CGPath] {
    let ball = CGMutablePath(); ball.addEllipse(in: CGRect(x: 10.5, y: 1.7, width: 3, height: 3), transform: t)
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 12, y: 5.8), transform: t)
    body.addCurve(to: CGPoint(x: 16, y: 18), control1: CGPoint(x: 17.5, y: 9), control2: CGPoint(x: 18.6, y: 14.5), transform: t)
    body.addLine(to: CGPoint(x: 8, y: 18), transform: t)
    body.addCurve(to: CGPoint(x: 12, y: 5.8), control1: CGPoint(x: 5.4, y: 14.5), control2: CGPoint(x: 6.5, y: 9), transform: t)
    body.closeSubpath()
    let slit = CGMutablePath()
    slit.move(to: CGPoint(x: 14.8, y: 9.6), transform: t); slit.addLine(to: CGPoint(x: 10.6, y: 14), transform: t)
    let base = CGMutablePath(); base.addRoundedRect(in: CGRect(x: 7, y: 18, width: 10, height: 3), cornerWidth: 1, cornerHeight: 1, transform: t)
    return [ball, body, slit, base]
}

func outline(_ paths: [CGPath], width: CGFloat = SW) -> CGPath {
    paths.map { $0.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10) }
        .reduce(CGMutablePath() as CGPath) { $0.union($1) }
}

func folderBadge() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 13.6, y: 16.2))
    p.addQuadCurve(to: CGPoint(x: 14.5, y: 15.3), control: CGPoint(x: 13.6, y: 15.3))
    p.addLine(to: CGPoint(x: 16.6, y: 15.3)); p.addLine(to: CGPoint(x: 17.6, y: 16.3)); p.addLine(to: CGPoint(x: 21.1, y: 16.3))
    p.addQuadCurve(to: CGPoint(x: 22, y: 17.2), control: CGPoint(x: 22, y: 16.3))
    p.addLine(to: CGPoint(x: 22, y: 20.6))
    p.addQuadCurve(to: CGPoint(x: 21.1, y: 21.5), control: CGPoint(x: 22, y: 21.5))
    p.addLine(to: CGPoint(x: 14.5, y: 21.5))
    p.addQuadCurve(to: CGPoint(x: 13.6, y: 20.6), control: CGPoint(x: 13.6, y: 21.5))
    p.closeSubpath()
    return p
}

let file = outline(mitreParts(.identity))
let s: CGFloat = 0.86
let shrink = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: 9.6 - 12 * s, ty: 11.4 - 12 * s)
let badge = folderBadge()
let knockout = badge.union(badge.copy(strokingWithWidth: SW + 2 * 1.4, lineCap: .round, lineJoin: .round, miterLimit: 10))
let folder = outline(mitreParts(shrink)).subtracting(knockout).union(outline([badge]))

// Template v3 geometry: Regular-S baseline y=696, capline 625.541 (cap height 70.459).
let scale: CGFloat = 4.6
let capMid: CGFloat = -70.459 / 2
/// SF Symbols의 크기 비율: Small 0.783, Medium 1, Large 1.29. 세 크기 모두 대문자 높이 가운데에 맞춘다.
let symbolScales: [(name: String, baseline: CGFloat, factor: CGFloat)] = [("S", 696, 0.783), ("M", 1126, 1.0), ("L", 1556, 1.29)]

func svgPath(_ path: CGPath, xOffset: CGFloat, factor: CGFloat) -> String {
    let k = scale * factor
    func f(_ p: CGPoint) -> String { String(format: "%.3f %.3f", (p.x - xOffset) * k, (p.y - 12) * k + capMid) }
    var d = ""
    path.applyWithBlock { e in
        let pts = e.pointee.points
        switch e.pointee.type {
        case .moveToPoint: d += "M\(f(pts[0]))"
        case .addLineToPoint: d += "L\(f(pts[0]))"
        case .addQuadCurveToPoint: d += "Q\(f(pts[0])) \(f(pts[1]))"
        case .addCurveToPoint: d += "C\(f(pts[0])) \(f(pts[1])) \(f(pts[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func template(_ path: CGPath, name: String) -> String {
    let box = path.boundingBoxOfPath
    let margin: CGFloat = 1.0
    let left = box.minX - margin
    let x0: CGFloat = 1391.3
    let margins = symbolScales.map { size in
        let width = (box.width + 2 * margin) * scale * size.factor
        let top = String(format: "%.3f", size.baseline - 95.215), bottom = String(format: "%.3f", size.baseline + 24.121)
        return """
              <line id="left-margin-Regular-\(size.name)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(x0)" x2="\(x0)" y1="\(top)" y2="\(bottom)"/>
              <line id="right-margin-Regular-\(size.name)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(String(format: "%.3f", x0 + width))" x2="\(String(format: "%.3f", x0 + width))" y1="\(top)" y2="\(bottom)"/>
        """
    }.joined(separator: "\n")
    let glyphs = symbolScales.map { size in
        """
              <g id="Regular-\(size.name)" transform="matrix(1 0 0 1 \(x0) \(Int(size.baseline)))">
               <path d="\(svgPath(path, xOffset: left, factor: size.factor))"/>
              </g>
        """
    }.joined(separator: "\n")
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!--Generator: scripts/design/generate-bishop-symbols.swift-->
    <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
    <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
     <!--glyph: "\(name)", point size: 100.0-->
     <g id="Notes">
      <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 263 1933)">Template v.3.0</text>
     </g>
     <g id="Guides">
      <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="696" y2="696"/>
      <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="625.541" y2="625.541"/>
      <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1126" y2="1126"/>
      <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
      <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1556" y2="1556"/>
      <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
    \(margins)
     </g>
     <g id="Symbols">
    \(glyphs)
     </g>
    </svg>

    """
}

let catalog = CommandLine.arguments[1]
for (name, path) in [("fianchetto.bishop", file), ("fianchetto.bishop.folder", folder)] {
    let set = "\(catalog)/\(name).symbolset"
    try FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    try template(path, name: name).write(toFile: "\(set)/\(name).svg", atomically: true, encoding: .utf8)
    let contents = """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "symbols" : [
        {
          "filename" : "\(name).svg",
          "idiom" : "universal"
        }
      ]
    }

    """
    try contents.write(toFile: "\(set)/Contents.json", atomically: true, encoding: .utf8)
}
