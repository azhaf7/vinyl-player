import SwiftUI
import CoreGraphics

/// Pixel pets drawn from character grids (16 columns). Ported from the prototype's PETS / BODY / petFrame().
struct PetSpec {
    let id: String
    let name: String
    let palette: [Character: RGB]
    let head: [String]
    /// Panda: dark patches around the eyes and dark arms/feet.
    var panda = false
    /// Recolours the pixels around the eyes (e.g. the penguin's white face).
    var eyePatch: Character? = nil
    /// Listening time (minutes) needed before this pet can be picked; nil = always available.
    var unlockMinutes: Double? = nil

    static let body: [String] = [
        ".kooooooooooook.", ".kooooooooooook.", ".kooooooooooook.", ".kooooooooooook.", ".kooooooooooook.",
        ".kppoookkoooppk.", "..kooooooooook..", "..kkoollllookk..", ".kokollllllokok.", "..kooollllooook.",
        "..kooooooooook..", "..koook..koook..", "..kkkkk..kkkkk..",
    ]

    static func pal(k: String, o: String, l: String, p: String, d: String) -> [Character: RGB] {
        ["k": RGB(hex: k), "o": RGB(hex: o), "l": RGB(hex: l), "p": RGB(hex: p), "w": .white,
         "h": RGB(hex: "#2b2b30"), "c": RGB(hex: "#e0565b"), "d": RGB(hex: d),
         "g": RGB(hex: "#121214"), "s": RGB(hex: "#5b6b8c")]
    }

    static let all: [PetSpec] = [
        PetSpec(id: "cat", name: "Mochi", palette: pal(k: "#3a2a22", o: "#f0a860", l: "#ffe3bf", p: "#f59a9a", d: "#d98a48"),
                head: ["..kk........kk..", "..kpk......kpk..", "..kppkkkkkkppk.."]),
        PetSpec(id: "panda", name: "Bao", palette: pal(k: "#26262b", o: "#f4f1ea", l: "#ffffff", p: "#f3a6b0", d: "#3a3a42"),
                head: [".kkk........kkk.", ".kddk......kddk.", "..kkkkkkkkkkkk.."], panda: true),
        PetSpec(id: "frog", name: "Pip", palette: pal(k: "#24341f", o: "#8fcf6a", l: "#e6f2b8", p: "#f0a0a0", d: "#6fae4e"),
                head: ["................", "...kkkk..kkkk...", "..kooookkoooook."]),
        PetSpec(id: "bunny", name: "Tofu", palette: pal(k: "#3b3046", o: "#ece6f5", l: "#ffffff", p: "#f5a3c0", d: "#cfc6de"),
                head: ["...kk......kk...", "...kpk....kpk...", "...kpk....kpk...", "...kpk....kpk...", "..kkpkkkkkkpkk.."]),
        PetSpec(id: "fox", name: "Kiki", palette: pal(k: "#3a1f14", o: "#e8783a", l: "#fff4e6", p: "#f59a9a", d: "#c45f28"),
                head: [".k............k.", ".kok........kok.", ".kookkkkkkkkook."]),
        PetSpec(id: "penguin", name: "Nori", palette: pal(k: "#15171c", o: "#323844", l: "#f4f4f4", p: "#f6a96b", d: "#262b35"),
                head: ["................", "....kkkkkkkk....", "..kkkkkkkkkkkk.."], eyePatch: "l"),
        PetSpec(id: "dog", name: "Biscuit", palette: pal(k: "#3a2616", o: "#d9a066", l: "#f6e3c6", p: "#f59a9a", d: "#8a5a32"),
                head: ["................", ".kkk........kkk.", "kddk.kkkkkk.kddk"]),
        PetSpec(id: "hamster", name: "Peanut", palette: pal(k: "#3d2a1c", o: "#f2c48d", l: "#fff6e8", p: "#f7a1a1", d: "#d99a5b"),
                head: ["................", "...kkk....kkk...", "..kpppkkkkpppk.."]),
        PetSpec(id: "duck", name: "Quack", palette: pal(k: "#3a2e10", o: "#ffd34d", l: "#fff3b0", p: "#ff9f43", d: "#e6b422"),
                head: ["................", ".....kkkkkk.....", "...kkoooooookk.."]),
        PetSpec(id: "dragon", name: "Ember", palette: pal(k: "#2a1f45", o: "#8b6cd9", l: "#d9c8ff", p: "#ff8fb1", d: "#5b3fb0"),
                head: [".k............k.", ".kdk........kdk.", "..kdkkkkkkkkdk.."]),
    ]

    static func at(_ i: Int) -> PetSpec { all[max(0, min(all.count - 1, i))] }
}

enum PetArms: String { case down, up }
enum PetEyes: String { case open, look, blink, happy, sleep }

/// Things unlocked by listening. Pets with `unlockMinutes` are unlocked the same way.
enum PetUnlock: String, CaseIterable {
    case headphones, sunglasses

    var minutes: Double { self == .headphones ? 10 : 60 }
    var title: String { self == .headphones ? "Headphones" : "Sunglasses" }
}
enum PetLegs: String { case stand = "", a, b }

struct PetPose: Hashable {
    var arms: PetArms = .down
    var eyes: PetEyes = .open
    var legs: PetLegs = .stand
    var headphones = false
    var sunglasses = false
}

/// Builds (and caches) one sprite frame as a 1-pixel-per-cell CGImage. Scale it with `.interpolation(.none)`.
final class PetSpriteCache {
    static let shared = PetSpriteCache()
    private var cache: [String: CGImage] = [:]
    private let lock = NSLock()

    func image(pet: Int, pose: PetPose, body: RGB? = nil) -> CGImage? {
        let key = "\(pet)|\(pose.arms.rawValue)|\(pose.eyes.rawValue)|\(pose.legs.rawValue)|\(pose.headphones)|\(pose.sunglasses)|\(body?.hex ?? "")"
        lock.lock(); defer { lock.unlock() }
        if let img = cache[key] { return img }
        var palette = PetSpec.at(pet).palette
        if let body { palette["o"] = body; palette["d"] = body.darker(0.28) }
        let img = Self.render(grid: Self.grid(pet: pet, pose: pose), palette: palette)
        cache[key] = img
        return img
    }

    /// Sprite height in cells for a pet (head rows + body).
    static func rows(pet: Int) -> Int { PetSpec.at(pet).head.count + PetSpec.body.count }

    static func grid(pet: Int, pose: PetPose) -> [[Character]] {
        let P = PetSpec.at(pet)
        var g: [[Character]] = (P.head + PetSpec.body).map { row in
            var chars = Array(row)
            while chars.count < 16 { chars.append(".") }
            return Array(chars.prefix(16))
        }
        let o = P.head.count - 3 // row offset vs base (eyes at base rows 5-7)
        func R(_ r: Int) -> Int { r + o }
        func set(_ r: Int, _ c: Int, _ ch: Character) {
            guard r >= 0, r < g.count, c >= 0, c < 16 else { return }
            g[r][c] = ch
        }
        for c0 in [4, 10] {
            switch pose.eyes {
            case .open, .look:
                let c = c0 + (pose.eyes == .look ? 1 : 0)
                for r in 5...7 { set(R(r), c, "k"); set(R(r), c + 1, "k") }
                set(R(5), c, "w")
            case .blink, .sleep:
                set(R(6), c0, "k"); set(R(6), c0 + 1, "k")
            case .happy:
                set(R(6), c0, "k"); set(R(6), c0 + 1, "k")
                set(R(7), c0 == 4 ? 3 : 12, "k")
                set(R(8), 7, "p"); set(R(8), 8, "p")
            }
            if let patch: Character = P.panda ? "d" : P.eyePatch {
                for r in 4...8 {
                    for c in [c0 - 1, c0, c0 + 1, c0 + 2] where c >= 0 && c < 16 && g[R(r)][c] == "o" { g[R(r)][c] = patch }
                }
            }
        }
        if pose.arms == .up {
            set(R(11), 1, "."); set(R(11), 2, "k"); set(R(11), 13, "k"); set(R(11), 14, ".")
            set(R(8), 0, "k"); set(R(9), 0, "k"); set(R(9), 1, "o"); set(R(10), 0, "k"); set(R(10), 1, "o"); set(R(11), 1, "k")
            set(R(8), 15, "k"); set(R(9), 15, "k"); set(R(9), 14, "o"); set(R(10), 15, "k"); set(R(10), 14, "o"); set(R(11), 14, "k")
        }
        let last = g.count - 1
        if pose.eyes == .sleep {
            set(0, 13, "k"); set(0, 14, "k"); set(0, 15, "k"); set(1, 14, "k"); set(2, 13, "k"); set(2, 14, "k"); set(2, 15, "k")
        }
        if pose.headphones {
            for c in 4...11 { set(R(2), c, "h") }
            for c in [2, 3, 12, 13] { set(R(2) + ((c == 2 || c == 13) ? 1 : 0), c, "h") }
            for r in R(5)...R(7) { set(r, 0, "h"); set(r, 1, "h"); set(r, 14, "h"); set(r, 15, "h") }
            set(R(6), 0, "c"); set(R(6), 15, "c")
        }
        if pose.sunglasses && pose.eyes != .sleep {
            for c in [3, 4, 5, 6, 9, 10, 11, 12] { set(R(5), c, "g"); set(R(6), c, "g") }
            set(R(5), 7, "g"); set(R(5), 8, "g")
            set(R(5), 4, "s"); set(R(5), 10, "s")
        }
        switch pose.legs {
        case .a: g[last - 1] = Array(".koook....koook."); g[last] = Array(".kkkkk....kkkkk.")
        case .b: g[last - 1] = Array("...kook..kook..."); g[last] = Array("...kkkk..kkkk...")
        case .stand: break
        }
        if P.panda {
            for r in [R(11), last - 1] { g[r] = g[r].map { $0 == "o" ? "d" : $0 } }
        }
        return g
    }

    static func render(grid: [[Character]], palette: [Character: RGB]) -> CGImage? {
        let w = 16, h = grid.count
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in grid.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = palette[ch] else { continue }
                let i = (y * w + x) * 4
                px[i] = UInt8(c.r * 255); px[i + 1] = UInt8(c.g * 255); px[i + 2] = UInt8(c.b * 255); px[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// A pet sprite at `pixel` points per cell, bottom-aligned in a 16-cell-wide box.
struct PetSprite: View {
    let pet: Int
    let pose: PetPose
    var pixel: CGFloat = 3
    /// Custom body colour (Style tab).
    var tint: RGB? = nil

    var body: some View {
        if let img = PetSpriteCache.shared.image(pet: pet, pose: pose, body: tint) {
            Image(decorative: img, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: 16 * pixel, height: CGFloat(img.height) * pixel)
        }
    }
}
