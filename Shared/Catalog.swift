import SwiftUI

/// One song. The mock playback layer uses `Catalog.tracks`; real sources build these from their metadata.
struct Track: Codable, Hashable {
    var title: String
    var artist: String
    var duration: Double      // seconds
    var bpm: Double
    var tintHex: String       // used until the real cover's colour is known
    var artworkURL: String? = nil   // from the music app, when it provides one
    var sourceID: String? = nil     // the music app's id for the song

    /// Cache key shared by artwork lookup, custom covers and the widget snapshot.
    var key: String { (title + "|" + artist).lowercased() }
    var fallbackTint: RGB { RGB(hex: tintHex) }
}

enum Catalog {
    static let tracks: [Track] = [
        Track(title: "Blinding Lights", artist: "The Weeknd", duration: 200, bpm: 86, tintHex: "#5a78c8"),
        Track(title: "Dreams", artist: "Fleetwood Mac", duration: 257, bpm: 120, tintHex: "#d9784a"),
        Track(title: "Get Lucky", artist: "Daft Punk", duration: 248, bpm: 116, tintHex: "#3fa58a"),
        Track(title: "Redbone", artist: "Childish Gambino", duration: 327, bpm: 80, tintHex: "#e0a24a"),
        Track(title: "Electric Feel", artist: "MGMT", duration: 229, bpm: 103, tintHex: "#7aa860"),
        Track(title: "Heat Waves", artist: "Glass Animals", duration: 239, bpm: 81, tintHex: "#c86aa8"),
    ]

    /// Tracks 1–3 are side A, 4–6 side B.
    static func side(of index: Int) -> String { index < 3 ? "A" : "B" }
}

/// Record colours offered in the Records tab.
struct VinylStyle: Hashable {
    let name: String
    let base: RGB
    let ridge: RGB
    let edge: RGB
    let edge2: RGB

    static let all: [VinylStyle] = [
        VinylStyle(name: "Classic", base: RGB(hex: "#101012"), ridge: RGB(hex: "#1c1c20"), edge: RGB(hex: "#050506"), edge2: RGB(hex: "#1f1f24")),
        VinylStyle(name: "Oxblood", base: .oklch(0.3, 0.1, 22), ridge: .oklch(0.36, 0.11, 22), edge: .oklch(0.2, 0.07, 22), edge2: .oklch(0.34, 0.1, 22)),
        VinylStyle(name: "Ocean", base: .oklch(0.32, 0.09, 245), ridge: .oklch(0.38, 0.1, 245), edge: .oklch(0.2, 0.06, 245), edge2: .oklch(0.36, 0.09, 245)),
        VinylStyle(name: "Mustard", base: .oklch(0.66, 0.12, 82), ridge: .oklch(0.72, 0.12, 82), edge: .oklch(0.5, 0.1, 75), edge2: .oklch(0.66, 0.11, 80)),
        VinylStyle(name: "Smoke", base: .oklch(0.42, 0.01, 260), ridge: .oklch(0.5, 0.01, 260), edge: .oklch(0.3, 0.01, 260), edge2: .oklch(0.45, 0.01, 260)),
    ]

    static func at(_ i: Int) -> VinylStyle { all[max(0, min(all.count - 1, i))] }
}

/// Abstract placeholder covers, shown until (or instead of) the real album art.
struct FallbackArt: View {
    let index: Int

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let rect = CGRect(origin: .zero, size: size)
            func circle(_ cx: Double, _ cy: Double, _ r: Double, _ c: RGB) {
                ctx.fill(Path(ellipseIn: CGRect(x: cx * size.width - r * s, y: cy * size.height - r * s, width: 2 * r * s, height: 2 * r * s)), with: .color(c.color))
            }
            switch ((index % 6) + 6) % 6 {
            case 0: // Blinding Lights
                ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [RGB.oklch(0.5, 0.12, 250).color, RGB.oklch(0.26, 0.08, 265).color]),
                                                           startPoint: CGPoint(x: size.width * 0.33, y: 0), endPoint: CGPoint(x: size.width * 0.67, y: size.height)))
                circle(0.34, 0.34, 0.187, .oklch(0.82, 0.13, 70))
            case 1: // Dreams
                let w = s / 14.6
                var x = 0.0, odd = false
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: w + 0.5, height: size.height)), with: .color((odd ? RGB.oklch(0.62, 0.15, 28) : RGB.oklch(0.72, 0.14, 35)).color))
                    x += w; odd.toggle()
                }
                circle(0.70, 0.62, 0.168, .oklch(0.22, 0.04, 30))
            case 2: // Get Lucky
                ctx.fill(Path(rect), with: .color(RGB.oklch(0.22, 0.05, 220).color))
                circle(0.5, 1.18, 0.59, .oklch(0.7, 0.14, 165))
                circle(0.72, 0.26, 0.062, .oklch(0.95, 0.03, 100))
            case 3: // Redbone
                ctx.fill(Path(rect), with: .color(RGB.oklch(0.62, 0.16, 25).color))
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.48)), with: .color(RGB.oklch(0.86, 0.1, 88).color))
            case 4: // Electric Feel
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let period = s / 8.5
                var r = (hypot(size.width, size.height) / 2 / period).rounded(.up) * period
                var dark = true
                ctx.fill(Path(rect), with: .color(RGB.oklch(0.9, 0.04, 100).color))
                while r > 0 {
                    let col = dark ? RGB.oklch(0.55, 0.1, 145) : RGB.oklch(0.9, 0.04, 100)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(col.color))
                    r -= period / 2; dark.toggle()
                }
            default: // Heat Waves
                let c = CGPoint(x: size.width / 2, y: size.height / 2), R = hypot(size.width, size.height)
                let cols: [RGB] = [.oklch(0.7, 0.14, 330), .oklch(0.85, 0.1, 85), .oklch(0.6, 0.12, 250), .oklch(0.3, 0.04, 280)]
                for (i, col) in cols.enumerated() {
                    ctx.fill(Wedge.path(center: c, radius: R, from: -45 + Double(i) * 90, to: 45 + Double(i) * 90), with: .color(col.color))
                }
            }
        }
    }
}

enum Wedge {
    /// A pie slice; angles in degrees, 0° = pointing right, increasing clockwise on screen.
    static func path(center c: CGPoint, radius r: Double, from a0: Double, to a1: Double) -> Path {
        var p = Path()
        p.move(to: c)
        let steps = max(2, Int(abs(a1 - a0) / 4))
        for i in 0...steps {
            let a = (a0 + (a1 - a0) * Double(i) / Double(steps)) * .pi / 180
            p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        p.closeSubpath()
        return p
    }
}
