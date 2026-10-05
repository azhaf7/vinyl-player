import SwiftUI
import AppKit

/// The tilted turntable: plinth, platter, record, tonearm. Every part is a flat layer placed in the deck plane
/// at its own height (`deckLayer(z:)`), which gives real perspective and thickness, as in the design's CSS 3D.
struct DeckView: View {
    let model: PlayerModel
    let art: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            DeckBase()
            RpmSwitch(model: model).deckLayer(z: -9.5).allowsHitTesting(false)
            StatusLED(on: model.motor).deckLayer(z: -9.5)
            RecordStack(model: model, art: art)
            ArmShadowLayer(model: model)
            TonearmLayer(model: model)
            // Hit areas at the projected positions (the 3D layers themselves don't take clicks).
            Ellipse()
                .fill(Color.clear)
                .contentShape(Ellipse())
                .frame(width: 248, height: 223)
                .offset(x: 30, y: 44)
                .onTapGesture { model.toggle() }
                .onHover { model.hoverOn = $0 }
            ForEach([33, 45], id: \.self) { r in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 27, height: 20)
                    .offset(x: r == 33 ? 262 : 289.5, y: 257)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { model.setRPM(r) } }
            }
        }
        .frame(width: Deck.size.width, height: Deck.size.height, alignment: .topLeading)
    }
}

// MARK: - Static parts

private struct DeckBase: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Plinth top
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Tokens.sandTop.color, Tokens.sandBottom.color], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.35), location: 0), .init(color: .clear, location: 0.08),
                                                             .init(color: .clear, location: 0.92), .init(color: .black.opacity(0.1), location: 1)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
                .at(18, 8, 308, 288)
                .deckLayer(z: -10)
                .allowsHitTesting(false)

            // Plinth front face, folded down from the front edge.
            Rectangle()
                .fill(LinearGradient(colors: [Tokens.plinthFrontTop.color, Tokens.plinthFrontBottom.color], startPoint: .top, endPoint: .bottom))
                .frame(width: 264, height: 10)
                .deckLayer(z: 0, local: Mat4.about(132, 0, Mat4.rotateX(-90) * Mat4.translate(0, 0, -10)) * Mat4.translate(40, 296, 0))
                .allowsHitTesting(false)

            // Platter shadow and platter (4 layers of metal for thickness).
            Circle()
                .fill(RadialGradient(stops: [.init(color: .black.opacity(0.6), location: 0.55), .init(color: .clear, location: 0.72)],
                                     center: .center, startRadius: 0, endRadius: 134 * 1.414))
                .blur(radius: 6)
                .at(20, 24, 268, 268)
                .deckLayer(z: -9.8)
                .allowsHitTesting(false)
            ForEach([-9.0, -8, -7, -6], id: \.self) { z in
                Circle()
                    .fill(LinearGradient(stops: [.init(color: Color(hex: "#2e2e33"), location: 0), .init(color: Color(hex: "#8c8c94"), location: 0.6),
                                                 .init(color: Color(hex: "#3a3a40"), location: 1)],
                                         startPoint: UnitPoint(x: 0.54, y: 0), endPoint: UnitPoint(x: 0.46, y: 1)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(z == -6 ? 0.25 : 0), lineWidth: 0.5))
                    .at(25, 19, 258, 258)
                    .deckLayer(z: z)
                    .allowsHitTesting(false)
            }

            // Tonearm base and post.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#4a4a50"), Color(hex: "#222226")], center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 17))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                .at(289, 29, 34, 34)
                .deckLayer(z: -9.5)
                .allowsHitTesting(false)
            ForEach(0..<10, id: \.self) { i in
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "#3a3a40"), Color(hex: "#a0a0a8")], startPoint: .top, endPoint: .bottom))
                    .at(300, 40, 12, 12)
                    .deckLayer(z: -9 + Double(i) * 1.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct StatusLED: View {
    let on: Bool
    var body: some View {
        Circle()
            .fill(on ? Tokens.accent.color : Color.white.opacity(0.14))
            .shadow(color: on ? Tokens.accent.opacity(0.8).color : .clear, radius: 4)
            .animation(.easeInOut(duration: 0.4), value: on)
            .at(310, 76, 6, 6)
            .allowsHitTesting(false)
    }
}

private struct RpmSwitch: View {
    let model: PlayerModel
    var body: some View {
        HStack(spacing: 2) {
            ForEach([33, 45], id: \.self) { r in
                Text("\(r)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(model.rpm == r ? 0.95 : 0.4))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(model.rpm == r ? 0.14 : 0)))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.rpmPill.color).shadow(color: .white.opacity(0.25), radius: 0, y: 1))
        .fixedSize()
        .offset(x: 256, y: 258)
    }
}

// MARK: - Record

/// The record and everything attached to it. Moves as one body for hover, swap (lift and slide away) and flip.
private struct RecordStack: View {
    let model: PlayerModel
    let art: NSImage?

    var body: some View {
        let style = VinylStyle.at(model.vinyl)
        let rec = Mat4.about(154, 148, .rotateY(model.recordFlip)) * Mat4.translate(0, model.recordY, model.recordZ)
        let local: (Double) -> Mat4 = { z in Mat4.translate(0, 0, z) * rec }

        ZStack(alignment: .topLeading) {
            // Edge thickness: five slices.
            ForEach([-5.0, -4, -3, -2, -1], id: \.self) { z in
                Circle()
                    .fill(LinearGradient(stops: [.init(color: style.edge.color, location: 0.3), .init(color: style.edge2.color, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .at(30, 24, 248, 248)
                    .deckLayer(z: 0, local: local(z))
                    .allowsHitTesting(false)
            }
            // Spinning surface: grooves, label art, spindle hole.
            SpinningSurface(style: style, art: art, artIndex: model.index, angle: model.discAngle)
                .at(30, 24, 248, 248)
                .deckLayer(z: 0, local: local(0))
                .allowsHitTesting(false)
            // Fixed light: the record turns under it.
            RecordSheen(opacityA: 0.11, opacityB: 0.08, peakA: 26, peakB: 206)
                .at(30, 24, 248, 248)
                .deckLayer(z: 0, local: local(1.4))
                .allowsHitTesting(false)
            RecordBevel()
                .at(30, 24, 248, 248)
                .deckLayer(z: 0, local: local(1.5))
                .allowsHitTesting(false)
            ForEach([1.5, 2.8, 4.1, 5.4, 6.7, 8.0], id: \.self) { z in
                Circle()
                    .fill(z == 8 ? AnyShapeStyle(RadialGradient(colors: [Color(hex: "#fafafc"), Color(hex: "#9a9aa0")], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 3.5))
                                 : AnyShapeStyle(LinearGradient(colors: [Color(hex: "#55555b"), Color(hex: "#b4b4ba")], startPoint: .top, endPoint: .bottom)))
                    .at(150.5, 144.5, 7, 7)
                    .deckLayer(z: 0, local: local(z))
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct SpinningSurface: View {
    let style: VinylStyle
    let art: NSImage?
    let artIndex: Int
    let angle: Double

    var body: some View {
        ZStack {
            if let img = DiscImage.make(style: style, diameter: 248, detailed: true) {
                Image(decorative: img, scale: 2).resizable()
            }
            // Label: album art inset 73 (Ø102) with a slight bevel.
            CoverArt(image: art, index: artIndex)
                .frame(width: 102, height: 102)
                .clipShape(Circle())
                .overlay(
                    ZStack {
                        Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                        Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 5)
                        Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 4).frame(width: 28, height: 28).blur(radius: 1)
                    }
                )
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            // Spindle hole.
            Circle()
                .fill(RadialGradient(stops: [.init(color: .black, location: 0.4), .init(color: Color(hex: "#1a1a1d"), location: 1)], center: .center, startRadius: 0, endRadius: 6))
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .frame(width: 12, height: 12)
        }
        .frame(width: 248, height: 248)
        .rotationEffect(.degrees(angle))
    }
}

private struct RecordBevel: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.07), .clear], center: .center, startRadius: 0, endRadius: 52))
                .frame(width: 149, height: 99)
                .position(x: 74, y: 55)
            Circle().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .clear, location: 0.15),
                                                         .init(color: .clear, location: 0.85), .init(color: .black.opacity(0.6), location: 1)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 2)
            Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        }
        .frame(width: 248, height: 248)
        .clipShape(Circle())
    }
}

// MARK: - Tonearm

/// Tonearm parts drawn in arm space: origin at the pivot, tube pointing down (+y).
private struct ArmShape: View {
    var shadow = false

    var body: some View {
        Canvas { ctx, _ in
            ctx.translateBy(x: 30, y: 50)
            func metal(_ stops: [(String, Double)], _ r: CGRect) -> GraphicsContext.Shading {
                if shadow { return .color(.black) }
                return .linearGradient(Gradient(stops: stops.map { .init(color: Color(hex: $0.0), location: $0.1) }),
                                       startPoint: CGPoint(x: r.minX, y: r.midY), endPoint: CGPoint(x: r.maxX, y: r.midY))
            }
            let cw = CGRect(x: -7, y: -40, width: 14, height: 26)
            ctx.fill(Path(roundedRect: cw, cornerRadius: 4), with: metal([("#3a3a3f", 0), ("#9a9aa1", 0.45), ("#44444a", 1)], cw))
            let tube = shadow ? CGRect(x: -2.5, y: -16, width: 5, height: 186) : CGRect(x: -2, y: -16, width: 4, height: 186)
            ctx.fill(Path(roundedRect: tube, cornerRadius: 2), with: metal([("#77777d", 0), ("#f4f4f7", 0.45), ("#8a8a90", 1)], tube))
            if !shadow {
                let g = CGRect(x: -9, y: -9, width: 18, height: 18)
                ctx.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.6), radius: 1.5, y: 1))
                    l.fill(Path(ellipseIn: g), with: .radialGradient(Gradient(stops: [.init(color: Color(hex: "#ececf0"), location: 0), .init(color: Color(hex: "#8a8a90"), location: 0.65), .init(color: Color(hex: "#55555b"), location: 1)]),
                                                                    center: CGPoint(x: -2.7, y: -3.6), startRadius: 0, endRadius: 14))
                }
            }
            var head = ctx
            head.translateBy(x: 0, y: 166)
            head.rotate(by: .degrees(22))
            let hs = CGRect(x: -6, y: 0, width: 12, height: 24)
            head.fill(Path(roundedRect: hs, cornerRadius: 3.5), with: metal([("#26262a", 0), ("#5c5c62", 0.5), ("#2c2c31", 1)], hs))
            if !shadow {
                head.stroke(Path(roundedRect: hs.insetBy(dx: 0.25, dy: 0.25), cornerRadius: 3.5), with: .color(.white.opacity(0.18)), lineWidth: 0.5)
                head.fill(Path(CGRect(x: -1.5, y: 22, width: 3, height: 3)), with: .color(Tokens.stylus.color))
            }
        }
        .frame(width: 60, height: 280)
    }
}

private struct ArmShadowLayer: View {
    let model: PlayerModel
    var body: some View {
        let h = model.armShadowH
        let local = Mat4.translate(-30, -50, 0) * Mat4.rotateZ(model.armSwing) * Mat4.translate(h * 0.35, h * 0.55, 1.6) * Mat4.translate(306, 46, 0)
        ArmShape(shadow: true)
            .blur(radius: 1.2 + h * 0.18)
            .opacity(model.armShadowOpacity)
            .deckLayer(z: 0, local: local)
            .allowsHitTesting(false)
    }
}

private struct TonearmLayer: View {
    let model: PlayerModel
    var body: some View {
        let local = Mat4.translate(-30, -50, 0) * Mat4.rotateX(model.armTilt) * Mat4.rotateZ(model.armSwing) * Mat4.translate(306, 46, 6)
        ArmShape()
            .deckLayer(z: 0, local: local)
            .allowsHitTesting(false)
    }
}
