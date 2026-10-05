import SwiftUI
import AppKit

/// Pre-rendered record surfaces (grooves, wedge sheen, groove bands). Rendered once per style and size,
/// then rotated as a bitmap, so spinning costs a transform rather than a redraw.
enum DiscImage {
    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    static func make(style: VinylStyle, diameter: CGFloat, scale: CGFloat = 2, detailed: Bool, ring: RGB = Tokens.labelRing) -> CGImage? {
        let key = "\(style.base.hex)|\(style.ridge.hex)|\(diameter)|\(scale)|\(detailed)|\(ring.hex)"
        lock.lock(); defer { lock.unlock() }
        if let img = cache[key] { return img }
        let px = Int((diameter * scale).rounded())
        guard px > 0, let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Work in points with y pointing down, like the design.
        ctx.translateBy(x: 0, y: CGFloat(px))
        ctx.scaleBy(x: scale, y: -scale)
        let R = diameter / 2, c = CGPoint(x: R, y: R)
        func disc(_ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

        ctx.addEllipse(in: disc(R)); ctx.clip()
        ctx.setFillColor(style.base.cgColor); ctx.fill(disc(R))

        // Grooves: repeating radial ridge every 2.3 pt.
        ctx.setStrokeColor(style.ridge.opacity(0.85).cgColor)
        ctx.setLineWidth(0.8)
        var r: CGFloat = 1.5
        while r < R {
            ctx.strokeEllipse(in: disc(r)); r += 2.3
        }

        // Four light wedges (repeating conic from 10°: light 0–45°, clear 45–90°).
        ctx.setFillColor(RGB.whiteAlpha(0.05).cgColor)
        for i in 0..<4 {
            let a0 = (10 + Double(i) * 90 - 90) * .pi / 180, a1 = a0 + .pi / 4
            ctx.move(to: c)
            ctx.addArc(center: c, radius: R, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.closePath(); ctx.fillPath()
        }

        if detailed {
            let k = diameter / 248 // the design's measurements are for the 248 pt deck record
            func grooveBand(_ inset: CGFloat, dark: Double, lightWidth: CGFloat, light: Double) {
                let rr = R - inset * k
                if light > 0 {
                    ctx.setStrokeColor(RGB.whiteAlpha(light).cgColor); ctx.setLineWidth(lightWidth * 2)
                    ctx.strokeEllipse(in: disc(rr))
                }
                if dark > 0 {
                    ctx.setStrokeColor(RGB.blackAlpha(dark).cgColor); ctx.setLineWidth(2)
                    ctx.strokeEllipse(in: disc(rr))
                }
            }
            grooveBand(4, dark: 0, lightWidth: 1, light: 0.03)
            ctx.setFillColor(ring.cgColor); ctx.fillEllipse(in: disc(R - 15 * k))
            ctx.setStrokeColor(RGB.whiteAlpha(0.05).cgColor); ctx.setLineWidth(1); ctx.strokeEllipse(in: disc(R - 15 * k + 0.5))
            ctx.setFillColor(RGB(hex: "#050506").cgColor); ctx.fillEllipse(in: disc(R - 17 * k))
        }
        let img = ctx.makeImage()
        cache[key] = img
        return img
    }
}

/// Album art: the real cover when we have one, otherwise the abstract placeholder.
struct CoverArt: View {
    let image: NSImage?
    let index: Int

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            FallbackArt(index: index)
        }
    }
}

/// A flat record with art on the label, used for the crate, share sheet and widgets.
struct MiniRecord: View {
    let diameter: CGFloat
    let style: VinylStyle
    let art: NSImage?
    let artIndex: Int
    /// Inset of the art from the record edge.
    let artInset: CGFloat
    /// Optional cream label ring drawn `ringWidth` outside the art.
    var ringWidth: CGFloat = 0
    var spindle: CGFloat = 0
    var sheen = true
    var ring: RGB = Tokens.labelRing

    var body: some View {
        ZStack {
            if let img = DiscImage.make(style: style, diameter: diameter, detailed: false) {
                Image(decorative: img, scale: 2).resizable()
            }
            if ringWidth > 0 {
                Circle().fill(ring.color).padding(artInset - ringWidth)
            }
            CoverArt(image: art, index: artIndex)
                .frame(width: diameter - 2 * artInset, height: diameter - 2 * artInset)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
            if spindle > 0 {
                Circle().fill(Color(red: 0.03, green: 0.03, blue: 0.04)).frame(width: spindle, height: spindle)
            }
            if sheen { RecordSheen(opacityA: 0.1, opacityB: 0.07) }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }
}

/// The fixed specular highlight (the record turns under it). CSS conic angles: 0° = up, clockwise.
struct RecordSheen: View {
    var opacityA: Double = 0.12
    var opacityB: Double = 0.08
    var peakA: Double = 28
    var peakB: Double = 206

    var body: some View {
        AngularGradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(opacityA), location: peakA / 360),
            .init(color: .white.opacity(0), location: (peakA + 26) / 360),
            .init(color: .white.opacity(0), location: 0.5),
            .init(color: .white.opacity(opacityB), location: peakB / 360),
            .init(color: .white.opacity(0), location: (peakB + 26) / 360),
            .init(color: .white.opacity(0), location: 1),
        ], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}

/// Square album sleeve with its sheen, as used by the share sheet and widgets.
struct Sleeve: View {
    let size: CGFloat
    let art: NSImage?
    let artIndex: Int
    var radius: CGFloat = 6

    var body: some View {
        CoverArt(image: art, index: artIndex)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                LinearGradient(stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .clear, location: 0.4), .init(color: .black.opacity(0.12), location: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 5, x: 4, y: 0)
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 6)
    }
}
