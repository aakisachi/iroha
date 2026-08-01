import AppKit
import CoreImage
import UniformTypeIdentifiers

// フォルダアイコンの生成・適用・解除を担当
final class IconPainter {
    static let shared = IconPainter()

    // macOS標準フォルダアイコン（青系）のおおよその色相（度）。ここからの回転で着色する
    private let baseHue: CGFloat = 205
    private var cache: [String: NSImage] = [:]
    private let ciContext = CIContext()

    func icon(for color: FolderColor) -> NSImage {
        if let img = cache[color.hex] { return img }
        let img = generate(color, size: 512)
        cache[color.hex] = img
        return img
    }

    // 設定画面のライブプレビュー用（カラーホイール操作中に大量生成されるためキャッシュしない・小さめ）
    func previewIcon(for color: FolderColor) -> NSImage {
        generate(color, size: 256)
    }

    private func generate(_ color: FolderColor, size: CGFloat) -> NSImage {
        let base = NSWorkspace.shared.icon(for: UTType.folder)
        let canvas = NSSize(width: size, height: size)
        base.size = canvas

        guard let tiff = base.tiffRepresentation,
              let ciInput = CIImage(data: tiff) else { return base }

        let (hue, sat, bri) = color.hsb
        var output = ciInput

        if sat < 0.12 {
            // 無彩色（グレー・黒・白系）: 彩度を落として明度を寄せる
            let filter = CIFilter(name: "CIColorControls")!
            filter.setValue(output, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)
            filter.setValue((bri - 0.75) * 0.4, forKey: kCIInputBrightnessKey)
            output = filter.outputImage ?? output
        } else {
            let rotate = CIFilter(name: "CIHueAdjust")!
            rotate.setValue(output, forKey: kCIInputImageKey)
            rotate.setValue((hue * 360 - baseHue) * .pi / 180, forKey: kCIInputAngleKey)
            output = rotate.outputImage ?? output

            // 選んだ色の彩度・明度に寄せる（回転だけだとくすむ）
            let adjust = CIFilter(name: "CIColorControls")!
            adjust.setValue(output, forKey: kCIInputImageKey)
            adjust.setValue(0.5 + sat * 0.85, forKey: kCIInputSaturationKey)
            adjust.setValue((bri - 0.85) * 0.25, forKey: kCIInputBrightnessKey)
            output = adjust.outputImage ?? output
        }

        guard let cg = ciContext.createCGImage(output, from: output.extent) else { return base }
        return NSImage(cgImage: cg, size: canvas)
    }

    // MARK: - 適用・解除

    // 「irohaが塗った」印として書き込む拡張属性（コピーしても付いてくる）
    private let markerName = "app.folderpainter.color"

    @discardableResult
    func paint(_ path: String, color: FolderColor) -> Bool {
        let ok = NSWorkspace.shared.setIcon(icon(for: color), forFile: path, options: [])
        if ok { writeMarker(path, color: color) }
        return ok
    }

    @discardableResult
    func unpaint(_ path: String) -> Bool {
        let ok = NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
        if ok { removeMarker(path) }
        return ok
    }

    func writeMarker(_ path: String, color: FolderColor) {
        let bytes = Array(color.hex.utf8)
        setxattr(path, markerName, bytes, bytes.count, 0, 0)
    }

    func marker(_ path: String) -> String? {
        let n = getxattr(path, markerName, nil, 0, 0, 0)
        guard n > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: n)
        getxattr(path, markerName, &buf, n, 0, 0)
        return String(bytes: buf, encoding: .utf8)
    }

    func removeMarker(_ path: String) {
        removexattr(path, markerName, 0)
    }

    // MARK: - 迷子救出（マーカーが無い時代の塗り残骸の判定）

    // 標準フォルダアイコンの形（アルファシルエット）。塗り残骸は色が違うだけで形は同じ
    private lazy var standardFolderAlpha: [UInt8] = alphaMask(of: NSWorkspace.shared.icon(for: UTType.folder))

    // このフォルダのカスタムアイコンが「色を変えた標準フォルダ」に見えるか
    // しきい値18: 実測で塗り残骸=約12、本物のカスタムアイコン=30以上（2026-08-02計測）
    func looksLikeTintedFolder(_ path: String) -> Bool {
        silhouetteDiff(path) < 18.0
    }

    // デバッグ用: 標準フォルダ形との平均アルファ差
    func silhouetteDiff(_ path: String) -> Double {
        let a = alphaMask(of: NSWorkspace.shared.icon(forFile: path))
        guard !a.isEmpty, a.count == standardFolderAlpha.count else { return 999 }
        var total = 0
        for i in 0..<a.count { total += abs(Int(a[i]) - Int(standardFolderAlpha[i])) }
        return Double(total) / Double(a.count)
    }

    private func alphaMask(of image: NSImage, size: Int = 32) -> [UInt8] {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return [] }
        var out = [UInt8]()
        out.reserveCapacity(size * size)
        for i in 0..<(size * size) { out.append(data[i * 4 + 3]) }
        return out
    }

    // 元からカスタムアイコンが付いているか（フォルダ直下の "Icon\r" ファイルで判定）
    func hasCustomIcon(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/Icon\r")
    }

    // 目視確認用: 代表色をPNGに書き出す
    func writePNGs(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, hex) in FolderColor.legacyNames {
            let img = icon(for: FolderColor(hex: hex))
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: dir.appendingPathComponent("folder_\(name).png"))
        }
    }
}
