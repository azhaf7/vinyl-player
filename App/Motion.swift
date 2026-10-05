import SwiftUI

/// CSS `cubic-bezier(x1, y1, x2, y2)` timing function.
struct CubicBezier {
    private let cx, bx, ax, cy, by, ay: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }

    private func sx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sy(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {
            let e = sx(t) - x
            if abs(e) < 1e-6 { return sy(t) }
            let d = dx(t)
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        while hi - lo > 1e-6 {
            if sx(t) < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sy(t)
    }

    static let armSwing = CubicBezier(0.34, 1.22, 0.52, 1)
    static let armLift = CubicBezier(0.45, 0, 0.2, 1)
    static let ease = CubicBezier(0.25, 0.1, 0.25, 1)
}

/// A value that eases to its target like a CSS transition: a big change restarts the transition from the
/// current value, small changes (e.g. the arm following the groove) are tracked smoothly.
struct Tween {
    let duration: Double // ms
    let curve: CubicBezier
    var jump: Double = 0.5

    private(set) var from: Double
    private(set) var target: Double
    private var elapsed: Double

    init(_ value: Double, duration: Double, curve: CubicBezier, jump: Double = 0.5) {
        self.duration = duration; self.curve = curve; self.jump = jump
        from = value; target = value; elapsed = duration
    }

    var value: Double { from + (target - from) * curve(min(1, elapsed / duration)) }
    var settled: Bool { elapsed >= duration }

    mutating func set(_ newTarget: Double) {
        if abs(newTarget - target) > jump {
            from = value; elapsed = 0
        }
        target = newTarget
    }

    mutating func snap(_ v: Double) { from = v; target = v; elapsed = duration }

    mutating func advance(_ dt: Double) { elapsed = min(duration, elapsed + dt) }
}

/// Exponential approach: `x += (target - x) * (1 - e^(-dt/τ))`.
@inline(__always) func approach(_ x: Double, _ target: Double, dt: Double, tau: Double) -> Double {
    x + (target - x) * (1 - exp(-dt / tau))
}

// MARK: - 3D deck projection

/// Row-vector 4×4 matrix (`p' = p · M`), matching CSS transform composition order when concatenated left to right.
struct Mat4 {
    var m: [Double]

    static let identity = Mat4(m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    static func translate(_ x: Double, _ y: Double, _ z: Double) -> Mat4 {
        Mat4(m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1])
    }

    /// CSS rotateX (y down): y' = y·cos − z·sin, z' = y·sin + z·cos.
    static func rotateX(_ deg: Double) -> Mat4 {
        let a = deg * .pi / 180, c = cos(a), s = sin(a)
        return Mat4(m: [1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0, 0, 0, 0, 1])
    }

    /// CSS rotateY: x' = x·cos + z·sin, z' = −x·sin + z·cos.
    static func rotateY(_ deg: Double) -> Mat4 {
        let a = deg * .pi / 180, c = cos(a), s = sin(a)
        return Mat4(m: [c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1])
    }

    /// CSS rotateZ / rotate (clockwise on screen with y down).
    static func rotateZ(_ deg: Double) -> Mat4 {
        let a = deg * .pi / 180, c = cos(a), s = sin(a)
        return Mat4(m: [c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    }

    static func perspective(_ d: Double) -> Mat4 {
        Mat4(m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, -1 / d, 0, 0, 0, 1])
    }

    /// Rotation about a point (CSS transform-origin).
    static func about(_ x: Double, _ y: Double, _ r: Mat4) -> Mat4 {
        translate(-x, -y, 0) * r * translate(x, y, 0)
    }

    static func * (a: Mat4, b: Mat4) -> Mat4 {
        var r = [Double](repeating: 0, count: 16)
        for i in 0..<4 {
            for j in 0..<4 {
                var s = 0.0
                for k in 0..<4 { s += a.m[i * 4 + k] * b.m[k * 4 + j] }
                r[i * 4 + j] = s
            }
        }
        return Mat4(m: r)
    }

    /// Projection for points on the z = 0 plane of the layer.
    var projection: ProjectionTransform {
        var p = ProjectionTransform()
        p.m11 = CGFloat(m[0]); p.m12 = CGFloat(m[1]); p.m13 = CGFloat(m[3])
        p.m21 = CGFloat(m[4]); p.m22 = CGFloat(m[5]); p.m23 = CGFloat(m[7])
        p.m31 = CGFloat(m[12]); p.m32 = CGFloat(m[13]); p.m33 = CGFloat(m[15])
        return p
    }
}

/// The deck plane: 344×300, `perspective: 1000px; perspective-origin: 50% 30%`, child `rotateX(30deg)`.
enum Deck {
    static let size = CGSize(width: 344, height: 300)
    static let view: Mat4 = Mat4.about(172, 150, .rotateX(30)) * Mat4.about(172, 90, .perspective(1000))

    /// Transform for a layer that lives at height `z` above the plane (after an optional local transform).
    static func layer(z: Double, local: Mat4 = .identity) -> ProjectionTransform {
        (local * Mat4.translate(0, 0, z) * view).projection
    }
}

extension View {
    /// Places plane-space content (a 344×300 canvas, top-left origin) onto the tilted deck at height `z`.
    func deckLayer(z: Double, local: Mat4 = .identity) -> some View {
        self.frame(width: Deck.size.width, height: Deck.size.height, alignment: .topLeading)
            .projectionEffect(Deck.layer(z: z, local: local))
    }

    /// Absolute positioning in the parent's top-left coordinate space, like CSS `left/top`.
    func at(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        self.frame(width: w, height: h).offset(x: x, y: y)
    }
}
