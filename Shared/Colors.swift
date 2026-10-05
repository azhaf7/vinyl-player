import SwiftUI

/// A plain sRGB colour that can be mixed, stored and turned into SwiftUI / Core Graphics colours.
struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `#rrggbb` (or `rrggbb`). Falls back to mid grey on bad input.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self.init(0.5, 0.5, 0.5); return }
        self.init(Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }

    /// CSS `oklch(L C H)` converted to sRGB (clamped to gamut).
    static func oklch(_ l: Double, _ c: Double, _ h: Double, _ alpha: Double = 1) -> RGB {
        let hr = h * .pi / 180
        let A = c * cos(hr), B = c * sin(hr)
        let l_ = l + 0.3963377774 * A + 0.2158037573 * B
        let m_ = l - 0.1055613458 * A - 0.0638541728 * B
        let s_ = l - 0.0894841775 * A - 1.2914855480 * B
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let b = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        func gamma(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return RGB(gamma(r), gamma(g), gamma(b), alpha)
    }

    var hex: String {
        func h(_ v: Double) -> String { String(format: "%02x", Int((min(1, max(0, v)) * 255).rounded())) }
        return "#" + h(r) + h(g) + h(b)
    }

    /// `color-mix(self amount, other)`: `amount` is the share of `self`.
    func mix(_ other: RGB, _ amount: Double) -> RGB {
        RGB(r * amount + other.r * (1 - amount), g * amount + other.g * (1 - amount),
            b * amount + other.b * (1 - amount), a * amount + other.a * (1 - amount))
    }

    func opacity(_ o: Double) -> RGB { RGB(r, g, b, o) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

extension RGB {
    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)
    static func whiteAlpha(_ a: Double) -> RGB { RGB(1, 1, 1, a) }
    static func blackAlpha(_ a: Double) -> RGB { RGB(0, 0, 0, a) }
}

extension Color {
    init(hex: String) { self = RGB(hex: hex).color }
}

/// Design tokens from the handoff.
enum Tokens {
    static let accent = RGB.oklch(0.78, 0.16, 45)          // LED, selection rings
    static let sandTop = RGB.oklch(0.83, 0.05, 75)
    static let sandBottom = RGB.oklch(0.76, 0.055, 68)
    static let plinthFrontTop = RGB.oklch(0.62, 0.05, 62)
    static let plinthFrontBottom = RGB.oklch(0.5, 0.045, 58)
    static let labelRing = RGB.oklch(0.86, 0.045, 80)
    static let stylus = RGB.oklch(0.72, 0.15, 45)
    static let rpmPill = RGB.oklch(0.32, 0.03, 60)
    static let sticker = RGB.oklch(0.86, 0.12, 80)
    static let fallbackTint = RGB(hex: "#8a6a4a")
}
