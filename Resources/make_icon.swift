// iroha アプリアイコン生成スクリプト
// 使い方: swift Resources/make_icon.swift <出力PNG>
// デザイン: 藍色グラデーションの角丸スクエアに、赤・黄・青のフォルダを扇状に3枚
import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// 背景: macOS流の角丸スクエア + 藍グラデーション
let inset: CGFloat = 100
let bgRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let bgColors = [
    NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.40, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.17, alpha: 1).cgColor,
]
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: bgColors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: size / 2, y: size),
                       end: CGPoint(x: size / 2, y: 0),
                       options: [])

// フォルダ形状（本体＋タブ）
func folderPath(w: CGFloat, h: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let r: CGFloat = 34
    let tabW = w * 0.44
    let tabH = h * 0.16
    p.addRoundedRect(in: CGRect(x: 0, y: 0, width: w, height: h - tabH),
                     cornerWidth: r, cornerHeight: r)
    p.addRoundedRect(in: CGRect(x: 0, y: h - tabH - r, width: tabW, height: tabH + r),
                     cornerWidth: r, cornerHeight: r)
    return p
}

struct Fan {
    let top: NSColor
    let bottom: NSColor
    let angle: CGFloat
    let dx: CGFloat
    let dy: CGFloat
}

let fans: [Fan] = [
    Fan(top: NSColor(calibratedRed: 1.00, green: 0.48, blue: 0.44, alpha: 1),
        bottom: NSColor(calibratedRed: 0.90, green: 0.26, blue: 0.30, alpha: 1),
        angle: 13, dx: -150, dy: 40),
    Fan(top: NSColor(calibratedRed: 1.00, green: 0.83, blue: 0.36, alpha: 1),
        bottom: NSColor(calibratedRed: 0.98, green: 0.66, blue: 0.16, alpha: 1),
        angle: 0, dx: 0, dy: 0),
    Fan(top: NSColor(calibratedRed: 0.46, green: 0.74, blue: 1.00, alpha: 1),
        bottom: NSColor(calibratedRed: 0.20, green: 0.51, blue: 0.96, alpha: 1),
        angle: -13, dx: 130, dy: -44),
]

let fw: CGFloat = 440
let fh: CGFloat = 360

for fan in fans {
    ctx.saveGState()
    ctx.translateBy(x: size / 2 + fan.dx, y: size / 2 + fan.dy)
    ctx.rotate(by: fan.angle * .pi / 180)
    ctx.translateBy(x: -fw / 2, y: -fh / 2)

    // 落ち影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 46,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(folderPath(w: fw, h: fh))
    ctx.setFillColor(fan.bottom.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 本体グラデーション
    ctx.addPath(folderPath(w: fw, h: fh))
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [fan.top.cgColor, fan.bottom.cgColor] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g,
                           start: CGPoint(x: fw / 2, y: fh),
                           end: CGPoint(x: fw / 2, y: 0),
                           options: [])
    ctx.restoreGState()
}

ctx.restoreGState()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("saved: \(outPath)")
