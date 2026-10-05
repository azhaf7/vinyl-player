import SwiftUI
import AppKit

/// A song someone shared: `vinyl://record?song=…&by=…&from=…&pet=…&spotify=…`
/// (the web page's fragment uses the same names).
struct SharedRecord: Codable, Hashable {
    var title: String
    var artist: String
    var from: String
    var pet: String
    var spotifyID: String?
    var artworkURL: String?
    var message: String?

    init?(url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = comps.queryItems ?? []
        if let frag = comps.fragment, let fragItems = URLComponents(string: "?" + frag)?.queryItems { items += fragItems }
        func value(_ k: String) -> String? {
            items.first(where: { $0.name == k })?.value?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        }
        guard let title = value("song") else { return nil }
        self.title = title
        artist = value("by") ?? ""
        from = value("from") ?? "A friend"
        pet = value("pet") ?? ""
        if let sp = value("spotify"), sp.count == 22, sp.allSatisfy({ $0.isLetter || $0.isNumber }) { spotifyID = sp }
        if let art = value("art"), art.hasPrefix("https://") { artworkURL = art }
    }

    var track: Track {
        Track(title: title, artist: artist, duration: 240, bpm: 100, tintHex: "#8a6a4a",
              artworkURL: artworkURL, sourceID: spotifyID.map { "spotify:track:" + $0 })
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

final class SharedRecordWindowController {
    static let shared = SharedRecordWindowController()
    private var window: NSWindow?

    func show(_ record: SharedRecord) {
        let view = SharedRecordView(record: record)
        if let window {
            window.contentView = NSHostingView(rootView: view)
        } else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor(red: 0x12 / 255, green: 0x10 / 255, blue: 0x13 / 255, alpha: 1)
            w.contentView = NSHostingView(rootView: view)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The native version of web/shared-record: a sealed sleeve; click it and the record slides out and spins.
struct SharedRecordView: View {
    let record: SharedRecord
    @ObservedObject private var artwork = ArtworkService.shared
    @State private var openedAt: Date?

    private let stageWidth: CGFloat = 480

    var body: some View {
        let _ = artwork.revision
        let art = artwork.image(for: record.track)
        let tint = artwork.tint(for: record.track)
        let opened = openedAt != nil

        ZStack {
            RadialGradient(colors: [tint.mix(RGB(hex: "#121013"), 0.45).color, Color(hex: "#121013")],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.9), value: tint)

            VStack(spacing: 32) {
                VStack(spacing: 6) {
                    Text(record.from + (record.pet.isEmpty ? "" : " & " + record.pet) + " sent you a record")
                        .font(.system(size: 13, weight: .semibold)).tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(opened ? "Now spinning" : "Something to listen to")
                        .font(.system(size: 26, weight: .bold)).tracking(-0.5)
                        .foregroundStyle(.white)
                }

                stage(art: art)

                if opened {
                    VStack(spacing: 18) {
                        VStack(spacing: 4) {
                            Text(record.title).font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(.white)
                            Text(record.artist).font(.system(size: 17)).foregroundStyle(.white.opacity(0.65))
                            if let m = record.message, !m.isEmpty {
                                Text("“\(m)”").font(.system(size: 15).italic()).foregroundStyle(.white.opacity(0.8)).padding(.top, 6)
                            }
                        }
                        .multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button { Spotify.play(id: record.spotifyID, title: record.title, artist: record.artist) } label: {
                                Text(record.spotifyID != nil ? "Play on my turntable" : "Find in Spotify").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                                    .padding(.horizontal, 22).frame(height: 46)
                                    .background(Capsule().fill(Color(hex: "#1ed760")))
                            }
                            Button { openAppleMusic() } label: {
                                Text("Apple Music").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 22).frame(height: 46)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                            }
                        }
                        .buttonStyle(PressStyle(pressed: 0.96))
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 48)
        }
        .frame(width: 560, height: 640)
    }

    private func stage(art: NSImage?) -> some View {
        let w = stageWidth, h = w * 320 / 560
        let disc = w * 0.54, sleeve = w * 0.57
        return ZStack(alignment: .topLeading) {
            TimelineView(.animation(paused: openedAt == nil)) { ctx in
                MiniRecord(diameter: disc, style: VinylStyle.at(0), art: art, artIndex: 0, artInset: LP.artInset(for: disc),
                           ringWidth: disc * 0.012, spindle: disc * LP.spindle, sheen: false)
                    .rotationEffect(.degrees(spinAngle(at: ctx.date)))
                    .overlay(RecordSheen())
                    .shadow(color: .black.opacity(0.55), radius: 20, x: 10, y: 18)
            }
            .offset(x: w * 0.02 + (openedAt == nil ? 0 : disc * 0.76), y: h * 0.02)

            ZStack(alignment: .topTrailing) {
                Sleeve(size: sleeve, art: art, artIndex: 0, radius: 8)
                if openedAt == nil {
                    Text("Tap to open")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "#241c16"))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Tokens.sticker.color))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
                        .rotationEffect(.degrees(6))
                        .offset(x: 14, y: 18)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    /// 33⅓ rpm with an exponential spin-up (τ 600 ms); the angle only accumulates.
    private func spinAngle(at date: Date) -> Double {
        guard let openedAt else { return 0 }
        let t = max(0, date.timeIntervalSince(openedAt)), tau = 0.6
        let full = 33.3 * 360 / 60 * (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 1)
        return (full * (t - tau * (1 - exp(-t / tau)))).truncatingRemainder(dividingBy: 360)
    }

    private func open() {
        guard openedAt == nil else { return }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1)) { openedAt = Date() }
        if Preferences.shared.sound { SoundEngine.shared.needleDrop() }
    }

    private var query: String {
        (record.title + " " + record.artist).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? record.title
    }

    private func openAppleMusic() {
        if let url = URL(string: "https://music.apple.com/search?term=" + query) { NSWorkspace.shared.open(url) }
    }
}
