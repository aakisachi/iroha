import AppKit
import SwiftUI

// フォルダに付ける色。"#RRGGBB" のHEX文字列で保持し、ほぼ無限の色を扱える。
// 旧バージョン（red/blue等の8色名）の保存データも読み込み時に自動変換する。
struct FolderColor: Equatable, Hashable {
    var hex: String // "#RRGGBB"（大文字）

    init(hex: String) {
        self.hex = FolderColor.normalizeHex(hex) ?? "#E5484D"
    }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? NSColor.systemRed.usingColorSpace(.sRGB)!
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        self.hex = String(format: "#%02X%02X%02X", r, g, b)
    }

    var nsColor: NSColor {
        var v: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255,
                       alpha: 1)
    }

    var color: Color { Color(nsColor: nsColor) }

    // 色相(0-1)・彩度・明度
    var hsb: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (nsColor.usingColorSpace(.sRGB) ?? nsColor).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }

    var label: String { hex }

    static func normalizeHex(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if !s.hasPrefix("#") { s = "#" + s }
        guard s.count == 7,
              s.dropFirst().allSatisfy({ $0.isHexDigit }) else { return nil }
        return s
    }

    // 旧8色名 → HEX（保存データ互換とCLIの入力補助）
    static let legacyNames: [String: String] = [
        "red": "#E5484D", "orange": "#F5A623", "yellow": "#F7CE45",
        "green": "#30C452", "blue": "#3B82F6", "purple": "#A855F7",
        "pink": "#F472B6", "gray": "#9CA3AF",
    ]

    static func parse(_ s: String) -> FolderColor? {
        if let hx = normalizeHex(s) { return FolderColor(hex: hx) }
        if let hx = legacyNames[s.lowercased()] { return FolderColor(hex: hx) }
        return nil
    }

    static let defaultColor = FolderColor(hex: "#E5484D")
}

// 保存形式は単一文字列（旧enumのraw値もここで吸収）
extension FolderColor: Codable {
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = FolderColor.parse(s) ?? .defaultColor
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}
