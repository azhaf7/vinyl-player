import SwiftUI
import AppKit

extension RGB {
    init?(color: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    func darker(_ k: Double) -> RGB { mix(.black, 1 - k) }
    func lighter(_ k: Double) -> RGB { mix(.white, 1 - k) }
}

/// The user's colour choices. `nil` means the design's default.
struct PlayerStyle: Codable, Equatable {
    var deck: RGB?
    var vinyl: RGB?
    var ring: RGB?
    var accent: RGB?
    var card: RGB?
    var pet: RGB?

    var deckTop: RGB { deck ?? Tokens.sandTop }
    var deckBottom: RGB { deck.map { $0.darker(0.08) } ?? Tokens.sandBottom }
    var deckFrontTop: RGB { deck.map { $0.darker(0.25) } ?? Tokens.plinthFrontTop }
    var deckFrontBottom: RGB { deck.map { $0.darker(0.4) } ?? Tokens.plinthFrontBottom }
    var labelRing: RGB { ring ?? Tokens.labelRing }
    var accentColor: RGB { accent ?? Tokens.accent }

    static let presets: [(name: String, style: PlayerStyle)] = [
        ("Classic", PlayerStyle()),
        ("Midnight", PlayerStyle(deck: RGB(hex: "#2b2f3a"), vinyl: RGB(hex: "#14161c"), ring: RGB(hex: "#c9d4ff"),
                                 accent: RGB(hex: "#7aa2ff"), card: RGB(hex: "#10131c"), pet: nil)),
        ("Bubblegum", PlayerStyle(deck: RGB(hex: "#f6c6d8"), vinyl: RGB(hex: "#e86aa0"), ring: RGB(hex: "#fff0f6"),
                                  accent: RGB(hex: "#ff5fa2"), card: RGB(hex: "#3a1f2c"), pet: RGB(hex: "#ffb3d1"))),
        ("Forest", PlayerStyle(deck: RGB(hex: "#a8b98a"), vinyl: RGB(hex: "#2f4a33"), ring: RGB(hex: "#efe6c8"),
                               accent: RGB(hex: "#8fd16a"), card: RGB(hex: "#1b261c"), pet: nil)),
        ("Ocean", PlayerStyle(deck: RGB(hex: "#9ec9e0"), vinyl: RGB(hex: "#1f4f7a"), ring: RGB(hex: "#e6f4ff"),
                              accent: RGB(hex: "#4cc3ff"), card: RGB(hex: "#0f2233"), pet: nil)),
    ]
}

extension VinylStyle {
    /// Index `all.count` is the user's own colour.
    static var customIndex: Int { all.count }

    static func custom(_ c: RGB) -> VinylStyle {
        VinylStyle(name: "Custom", base: c, ridge: c.lighter(0.08), edge: c.darker(0.45), edge2: c.lighter(0.04))
    }

    static func resolve(_ index: Int, custom: RGB?) -> VinylStyle {
        index >= all.count ? .custom(custom ?? RGB(hex: "#101012")) : at(index)
    }
}

private struct PlayerStyleKey: EnvironmentKey {
    static let defaultValue = PlayerStyle()
}

extension EnvironmentValues {
    var playerStyle: PlayerStyle {
        get { self[PlayerStyleKey.self] }
        set { self[PlayerStyleKey.self] = newValue }
    }
}
