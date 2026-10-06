import SwiftUI
import AppKit

/// Colours that change with the theme.
struct Ink {
    let dark: Bool
    var ink: Color { dark ? .white.opacity(0.94) : Color(hex: "#1d1a17") }
    var ink2: Color { dark ? .white.opacity(0.6) : Color(hex: "#1d1a17").opacity(0.62) }
    var ink3: Color { dark ? .white.opacity(0.45) : Color(hex: "#1d1a17").opacity(0.5) }
    var glass: Color { dark ? Color(.sRGB, red: 30 / 255, green: 30 / 255, blue: 34 / 255, opacity: 0.58) : Color(.sRGB, red: 246 / 255, green: 244 / 255, blue: 240 / 255, opacity: 0.72) }
    var button: Color { dark ? .white.opacity(0.93) : Color(hex: "#1d1a17") }
    var buttonInk: Color { dark ? Color(hex: "#141416") : Color(hex: "#f6f4f0") }
    var track: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }
    var hover: Color { dark ? .white.opacity(0.09) : .black.opacity(0.06) }
}

/// The whole desktop player column: pet zone (58) → card (344×384) → optional Share / Crate panel.
struct PlayerRoot: View {
    let model: PlayerModel
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var artwork = ArtworkService.shared
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool {
        switch prefs.theme {
        case .system: return scheme == .dark
        case .dark: return true
        case .light: return false
        }
    }

    var body: some View {
        let ink = Ink(dark: dark)
        let _ = artwork.revision
        let art = artwork.image(for: model.track)
        let tint = artwork.tint(for: model.track)

        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                PlayerCard(model: model, ink: ink, art: art, tint: tint)
                    .padding(.top, 58)
                if model.drawer != nil {
                    CratePanel(model: model, ink: ink)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            if prefs.showPet { PetView(model: model) }
        }
        .frame(width: 344, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.shareOpen)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.drawer)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.playerStyle, prefs.style)
    }
}

// MARK: - Card

struct GlassBackground: View {
    let ink: Ink
    let radius: CGFloat
    @Environment(\.playerStyle) private var pstyle
    var body: some View {
        ZStack {
            VisualEffectBlur(radius: radius)
            if let card = pstyle.card { card.opacity(ink.dark ? 0.66 : 0.6).color } else { ink.glass }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
    }
}

private struct PlayerCard: View {
    let model: PlayerModel
    let ink: Ink
    let art: NSImage?
    let tint: RGB

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            // Tint glow: radial at top centre, 22% (dark) / 19% (light), fading by 70%.
            Rectangle()
                .fill(RadialGradient(colors: [tint.opacity(ink.dark ? 0.22 : 0.19).color, .clear], center: .top, startRadius: 0, endRadius: 269 * 0.7))
                .scaleEffect(x: 413.0 / 269.0, y: 1, anchor: .top)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.8), value: tint)
            DeckView(model: model, art: art)
                .offset(y: -8)
            ProgressRow(model: model, ink: ink, tint: tint)
                .frame(width: 300, height: 18)
                .offset(x: 22, y: 302)
            InfoRow(model: model, ink: ink, art: art)
                .frame(width: 306, height: 44)
                .offset(x: 22, y: 330)
        }
        .frame(width: 344, height: 384, alignment: .topLeading)
        .background(GlassBackground(ink: ink, radius: 30))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.08), location: 0), .init(color: .clear, location: 0.01)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .contextMenu {
            Button(model.pendingPlaying ? "Pause" : "Play") { model.toggle() }
            Button("Next Song") { model.next() }
            Divider()
            Button("Library…") { LibraryWindowController.shared.show() }
            Button("Settings…") { LibraryWindowController.shared.show(.settings) }
            Toggle("Show the Pet", isOn: Binding(get: { Preferences.shared.showPet }, set: { Preferences.shared.showPet = $0 }))
            Menu("Show As") {
                ForEach(DisplayMode.allCases) { m in
                    Button(m.rawValue) { Preferences.shared.displayMode = m }
                }
            }
            Menu("Size") {
                ForEach(PlayerSize.allCases) { z in
                    Button((Preferences.shared.playerSize == z ? "✓ " : "") + z.rawValue) { Preferences.shared.playerSize = z }
                }
            }
        }
    }
}

private func fmt(_ s: Double) -> String {
    let v = max(0, Int(s))
    return "\(v / 60):" + String(format: "%02d", v % 60)
}

private struct ProgressRow: View {
    let model: PlayerModel
    let ink: Ink
    let tint: RGB

    var body: some View {
        HStack(spacing: 8) {
            Text(fmt(Double(model.elapsedSec)))
                .frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.track)
                    Capsule().fill(tint.color).frame(width: max(0, geo.size.width * model.progress))
                }
                .frame(height: 3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    model.seek(fraction: v.location.x / max(1, geo.size.width))
                })
            }
            Text("-" + fmt(model.duration - Double(model.elapsedSec)))
                .frame(width: 28, alignment: .trailing)
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(ink.ink3)
    }
}

private struct InfoRow: View {
    @Environment(\.playerStyle) private var pstyle
    let model: PlayerModel
    let ink: Ink
    let art: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(model.track.title)
                        .font(.system(size: 13, weight: .semibold)).tracking(-0.13)
                        .foregroundStyle(ink.ink)
                    if !(model.isLive && model.track.sourceID == nil) {
                        LikeButton(track: model.track, size: 11, tint: pstyle.accentColor.color)
                    }
                }
                if model.needsPermission {
                    Text("Click to allow access to your music app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(pstyle.accentColor.color)
                        .onTapGesture { model.service.openPermissionSettings() }
                        .help(model.serviceStatus)
                } else if model.showsStatus {
                    Text(model.serviceStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(ink.ink2)
                        .help(model.serviceStatus)
                } else {
                    Text(model.track.artist + " · Side " + model.side)
                        .font(.system(size: 12))
                        .foregroundStyle(ink.ink2)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                IconButton(symbol: "backward.end.fill", size: 32, ink: ink) { model.previous() }
                PlayButton(playing: model.playing, ink: ink) { model.toggle() }
                IconButton(symbol: "forward.end.fill", size: 32, ink: ink) { model.next() }
                if let url = model.shareURL() {
                    // Copy Link, Messages, WhatsApp, Telegram, Mail, AirDrop, More…: the song goes as a sealed record.
                    ShareOptions(url: url, title: model.track.title, message: ShareLinks.message(for: model.track)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ink.ink2)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                }
                IconButton(symbol: "line.3.horizontal", size: 30, ink: ink, selected: model.drawer != nil && model.drawer != .style) {
                    model.drawer = model.drawer == nil || model.drawer == .style ? .queue : nil; model.shareOpen = false
                }
                .help("Crate: up next, records and pets")
                IconButton(symbol: "paintpalette.fill", size: 28, ink: ink, selected: model.drawer == .style) {
                    model.drawer = model.drawer == .style ? nil : .style; model.shareOpen = false
                }
                .help("Colours and themes")
            }
        }
    }
}

struct PressStyle: ButtonStyle {
    var pressed: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressed : 1)
            .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.18), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let symbol: String
    let size: CGFloat
    let ink: Ink
    var selected = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size > 31 ? 13 : 12, weight: .semibold))
                .foregroundStyle(ink.ink2)
                .frame(width: size, height: size)
                .background(Circle().fill(selected ? ink.hover.opacity(2) : hover ? ink.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.16), value: hover)
    }
}

struct PlayButton: View {
    let playing: Bool
    let ink: Ink
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .offset(x: playing ? 0 : 1.5)
                .foregroundStyle(ink.buttonInk)
                .frame(width: 42, height: 42)
                .background(Circle().fill(hover && ink.dark ? Color.white : ink.button))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 7, y: 4)
                .scaleEffect(hover ? 1.07 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(pressed: 0.92 / 1.07))
        .onHover { hover = $0 }
        .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.18), value: hover)
    }
}

// MARK: - Pet

private struct PetView: View {
    @Environment(\.playerStyle) private var pstyle
    let model: PlayerModel

    var body: some View {
        let r = model.petRender
        let rows = CGFloat(PetSpriteCache.rows(pet: model.pet))
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(Color.black.opacity(0.45))
                .frame(width: 32, height: 5)
                .blur(radius: 2)
                .scaleEffect(r.shadow)
                .opacity(r.shadow)
                .offset(x: 8, y: 57)
            PetSprite(pet: model.pet, pose: r.pose, tint: pstyle.pet)
                .offset(y: 60 - rows * 3 - 1)
                .frame(width: 48, height: 60, alignment: .topLeading)
                .scaleEffect(x: r.sx * r.face, y: r.sy, anchor: .bottom)
                .rotationEffect(.degrees(r.tilt), anchor: .bottom)
                .offset(x: r.sway, y: -r.lift)
        }
        .frame(width: 48, height: 60, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { model.petTapped() }
        .offset(x: r.x, y: r.y - 60)
    }
}

// MARK: - Panels

private struct CratePanel: View {
    @Environment(\.playerStyle) private var pstyle
    @ObservedObject private var prefs = Preferences.shared
    let model: PlayerModel
    let ink: Ink
    @ObservedObject var artwork = ArtworkService.shared
    /// First record shown in the Up next / Recent strip, for the ‹ › buttons.
    @State private var stripStart = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    tab(model.isLive ? "Recent" : "Up next", .queue)
                    tab("Records", .records)
                    tab("Pets", .pets)
                    tab("Style", .style)
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
                Spacer()
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(ink.ink2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture { LibraryWindowController.shared.show(.settings) }
                    .help("All settings")
            }

            switch model.drawer {
            case .records?: records
            case .pets?: pets
            case .style?: styleTab
            default: queue
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 14, trailing: 12))
        .frame(width: 344, alignment: .leading)
        .background(GlassBackground(ink: ink, radius: 24))
    }

    private func tab(_ title: String, _ d: Drawer) -> some View {
        let on = model.drawer == d
        return Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(on ? (ink.dark ? Color.white.opacity(0.95) : Color(hex: "#1d1a17")) : (ink.dark ? Color.white.opacity(0.5) : Color(hex: "#1d1a17").opacity(0.55)))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? (ink.dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { model.drawer = d } }
    }

    private func ring(_ on: Bool) -> some View {
        Circle().strokeBorder(on ? pstyle.accentColor.color : Color.white.opacity(0.08), lineWidth: on ? 2 : 1)
    }

    private var queue: some View {
        let _ = artwork.revision
        let tracks = model.tracks
        // Sample songs: the queue from the current song on. Live: recently played, newest first.
        let order = model.isLive
            ? Array(stride(from: min(model.index, tracks.count - 1), through: max(0, model.index - 19), by: -1))
            : tracks.indices.map { (model.index + $0) % tracks.count }
        return ScrollViewReader { proxy in
          HStack(spacing: 6) {
            StepButton(symbol: "chevron.left", enabled: stripStart > 0, size: 24) { scrollStrip(-1, order, proxy) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(order.enumerated()), id: \.element) { n, i in
                        let t = tracks[i]
                        VStack(alignment: .leading, spacing: 6) {
                            MiniRecord(diameter: 84, style: VinylStyle.resolve(model.vinyl, custom: pstyle.vinyl), art: artwork.image(for: t), artIndex: i, artInset: LP.artInset(for: 84), spindle: 6)
                                .overlay(ring(n == 0))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(ink.ink)
                                Text(n == 0 ? (model.playing ? "Now playing" : "On deck") : model.isLive ? "Played" : n == 1 ? "Up next" : fmt(t.duration))
                                    .font(.system(size: 10)).foregroundStyle(ink.ink3)
                            }
                            .lineLimit(1)
                        }
                        .frame(width: 84)
                        .modifier(HoverLift())
                        .onTapGesture { model.swapTo(i) }
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 2, bottom: 6, trailing: 2))
            }
            StepButton(symbol: "chevron.right", enabled: stripStart < order.count - 3, size: 24) { scrollStrip(1, order, proxy) }
          }
        }
    }

    /// Moves the record strip three records along, smoothly.
    private func scrollStrip(_ dir: Int, _ order: [Int], _ proxy: ScrollViewProxy) {
        guard !order.isEmpty else { return }
        stripStart = max(0, min(order.count - 1, stripStart + dir * 3))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { proxy.scrollTo(order[stripStart], anchor: .leading) }
    }

    private var records: some View {
        let art = artwork.image(for: model.track)
        let custom = VinylStyle.custom(pstyle.vinyl ?? RGB(hex: "#101012"))
        return HStack(spacing: 0) {
            ForEach(Array((VinylStyle.all + [custom]).enumerated()), id: \.offset) { i, v in
                VStack(spacing: 6) {
                    MiniRecord(diameter: 46, style: v, art: art, artIndex: model.index, artInset: LP.artInset(for: 46), ring: pstyle.labelRing)
                        .overlay(ring(i == model.vinyl))
                        .onTapGesture { model.selectVinyl(i) }
                    if i == VinylStyle.customIndex {
                        ColorPicker("", selection: colorBinding(\.vinyl, RGB(hex: "#101012")), supportsOpacity: false)
                            .labelsHidden()
                            .controlSize(.mini)
                    } else {
                        Text(v.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.ink2)
                            .onTapGesture { model.selectVinyl(i) }
                    }
                }
                .modifier(HoverLift())
                if i < VinylStyle.all.count { Spacer(minLength: 4) }
            }
        }
        .padding(2)
    }

    // MARK: Style

    private func colorBinding(_ key: WritableKeyPath<PlayerStyle, RGB?>, _ fallback: RGB) -> Binding<Color> {
        Binding(
            get: { (prefs.style[keyPath: key] ?? fallback).color },
            set: { c in
                guard let rgb = RGB(color: c) else { return }
                prefs.style[keyPath: key] = RGB(rgb.r, rgb.g, rgb.b)
                if key == \PlayerStyle.vinyl { model.selectVinyl(VinylStyle.customIndex) }
            })
    }

    private func colorRow(_ title: String, _ key: WritableKeyPath<PlayerStyle, RGB?>, _ fallback: RGB) -> some View {
        HStack(spacing: 6) {
            ColorPicker(selection: colorBinding(key, fallback), supportsOpacity: false) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(ink.ink)
            }
            if prefs.style[keyPath: key] != nil {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(ink.ink3)
                    .onTapGesture { prefs.style[keyPath: key] = nil }
                    .help("Back to the default")
            }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(ink.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)))
    }

    private var styleTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Themes").font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.ink3)
            HStack(spacing: 0) {
                ForEach(Array(PlayerStyle.presets.enumerated()), id: \.offset) { i, preset in
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(preset.style.deckTop.color)
                            Circle().fill((preset.style.vinyl ?? RGB(hex: "#101012")).color).padding(7)
                            Circle().fill(preset.style.labelRing.color).frame(width: 12, height: 12)
                            Circle().fill(preset.style.accentColor.color).frame(width: 7, height: 7).offset(x: 17, y: -13)
                        }
                        .frame(width: 52, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(prefs.style == preset.style ? pstyle.accentColor.color : Color.white.opacity(0.08), lineWidth: prefs.style == preset.style ? 2 : 1))
                        Text(preset.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.ink2)
                    }
                    .modifier(HoverLift())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) { prefs.style = preset.style }
                        model.selectVinyl(preset.style.vinyl == nil ? 0 : VinylStyle.customIndex)
                    }
                    if i < PlayerStyle.presets.count - 1 { Spacer(minLength: 4) }
                }
            }
            HStack(spacing: 8) {
                colorRow("Accent", \.accent, Tokens.accent)
                Text("More colours in Settings")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ink.ink3)
                    .underline()
                    .onTapGesture { LibraryWindowController.shared.show(.settings) }
            }
        }
    }

    private var pets: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 8) {
                ForEach(Array(PetSpec.all.enumerated()), id: \.offset) { i, p in
                    let open = model.isPetUnlocked(i)
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06))
                            PetSprite(pet: i, pose: PetPose(eyes: open ? .open : .sleep), pixel: 2, tint: i == model.pet ? pstyle.pet : nil)
                                .opacity(open ? 1 : 0.3)
                                .saturation(open ? 1 : 0)
                                .padding(.bottom, 6)
                            if !open {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ink.ink2)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                    .padding(7)
                            }
                        }
                        .frame(height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(i == model.pet ? pstyle.accentColor.color : Color.white.opacity(0.08), lineWidth: i == model.pet ? 2 : 1))
                        Text(open ? p.name : minutesLabel(p.unlockMinutes ?? 0))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(open ? ink.ink2 : ink.ink3)
                    }
                    .modifier(HoverLift())
                    .onTapGesture { model.selectPet(i) }
                    .help(open ? p.name : "\(p.name) unlocks after \(minutesLabel(p.unlockMinutes ?? 0)) of listening")
                }
            }
            .padding(2)

            HStack(spacing: 8) {
                accessory(.headphones, on: model.wearPhones) { model.toggleHeadphones() }
                accessory(.sunglasses, on: model.wearShades) { model.toggleSunglasses() }
            }
            HStack(spacing: 6) {
                Image(systemName: model.wearScarf ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.wearScarf ? pstyle.accentColor.color : ink.ink3)
                Text("Scarf in the album's colour").foregroundStyle(ink.ink)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(ink.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleScarf() }

        }
    }

    private func minutesLabel(_ m: Double) -> String {
        m >= 60 ? (m.truncatingRemainder(dividingBy: 60) < 1 ? "\(Int(m / 60)) h" : String(format: "%.1f h", m / 60)) : "\(Int(m)) min"
    }

    private func accessory(_ u: PetUnlock, on: Bool, toggle: @escaping () -> Void) -> some View {
        let open = model.isUnlocked(u)
        return HStack(spacing: 6) {
            Image(systemName: open ? (on ? "checkmark.circle.fill" : "circle") : "lock.fill")
                .foregroundStyle(open && on ? pstyle.accentColor.color : ink.ink3)
            Text(open ? u.title : u.title + " · " + minutesLabel(u.minutes))
                .foregroundStyle(open ? ink.ink : ink.ink3)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(ink.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { if open { toggle() } }
    }
}

private struct HoverLift: ViewModifier {
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .offset(y: hover ? -3 : 0)
            .animation(.timingCurve(0.3, 1.3, 0.5, 1, duration: 0.2), value: hover)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}
