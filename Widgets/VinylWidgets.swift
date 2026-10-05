import WidgetKit
import SwiftUI
import AppIntents

@main
struct VinylWidgetBundle: WidgetBundle {
    var body: some Widget {
        VinylWidget()
    }
}

struct VinylWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: Provider()) { entry in
            VinylWidgetView(entry: entry)
        }
        .configurationDisplayName("Vinyl")
        .description("The record that's playing, with play, pause and skip.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct VinylEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
    let asleep: Bool
}

struct Provider: TimelineProvider {
    static let sleepAfter: TimeInterval = 20 * 60

    func placeholder(in context: Context) -> VinylEntry {
        VinylEntry(date: Date(), snap: .placeholder, asleep: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (VinylEntry) -> Void) {
        completion(entry(at: Date(), SharedStore.readSnapshot() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VinylEntry>) -> Void) {
        let now = Date(), s = SharedStore.readSnapshot() ?? .placeholder
        var entries = [entry(at: now, s)]
        if !s.isPlaying, let since = s.pausedSince, since.addingTimeInterval(Self.sleepAfter) > now {
            entries.append(VinylEntry(date: since.addingTimeInterval(Self.sleepAfter), snap: s, asleep: true))
        }
        let policy: TimelineReloadPolicy = s.isPlaying
            ? .after(now.addingTimeInterval(max(5, s.duration - s.elapsed(at: now))))
            : .never
        completion(Timeline(entries: entries, policy: policy))
    }

    private func entry(at date: Date, _ s: WidgetSnapshot) -> VinylEntry {
        let asleep = !s.isPlaying && (s.pausedSince.map { date.timeIntervalSince($0) > Self.sleepAfter } ?? false)
        return VinylEntry(date: date, snap: s, asleep: asleep)
    }
}

// MARK: - Look

struct WidgetLook {
    let dark: Bool
    let tint: RGB

    var background: LinearGradient {
        let from = dark ? tint.mix(RGB(hex: "#1f1c1a"), 0.30) : tint.mix(RGB(hex: "#f7f4ef"), 0.22)
        let to = dark ? RGB(hex: "#161412") : RGB(hex: "#ebe6df")
        // CSS 160°: towards the bottom, slightly right.
        return LinearGradient(colors: [from.color, to.color], startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
    }
    var ink: Color { dark ? .white : Color(hex: "#1d1a17") }
    var ink2: Color { dark ? .white.opacity(0.6) : Color(hex: "#1d1a17").opacity(0.62) }
    var ink3: Color { dark ? .white.opacity(0.45) : Color(hex: "#1d1a17").opacity(0.5) }
    var accent: Color { tint.mix(dark ? .white : .black, 0.7).color }
    var button: Color { dark ? RGB.oklch(0.93, 0.03, 80).color : Color(hex: "#1d1a17") }
    var buttonInk: Color { dark ? Color(hex: "#1b1816") : Color(hex: "#f6f4f0") }
    var track: Color { dark ? .white.opacity(0.12) : .black.opacity(0.1) }
}

/// Lays out content designed at `ref` size, scaled to fit the actual widget.
struct Fit<Content: View>: View {
    let ref: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width / ref.width, g.size.height / ref.height)
            content()
                .frame(width: ref.width, height: ref.height, alignment: .topLeading)
                .scaleEffect(k, anchor: .topLeading)
                .offset(x: (g.size.width - ref.width * k) / 2, y: (g.size.height - ref.height * k) / 2)
        }
    }
}

// MARK: - Views

struct VinylWidgetView: View {
    let entry: VinylEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let look = WidgetLook(dark: scheme == .dark, tint: entry.snap.tint)
        Group {
            switch family {
            case .systemSmall: SmallView(entry: entry, look: look)
            case .systemLarge: LargeView(entry: entry, look: look)
            default: MediumView(entry: entry, look: look)
            }
        }
        .containerBackground(for: .widget) { look.background }
    }
}

private func petPose(_ e: VinylEntry) -> PetPose {
    if e.asleep { return PetPose(arms: .down, eyes: .sleep, headphones: e.snap.headphones) }
    return e.snap.isPlaying ? PetPose(arms: .up, eyes: .happy, headphones: e.snap.headphones)
                            : PetPose(arms: .down, eyes: .open, headphones: e.snap.headphones)
}

private func statusLine(_ s: WidgetSnapshot) -> String {
    (s.isPlaying ? "Now spinning" : "Paused") + " · Side " + s.side
}

/// A record with the cream label ring, static rotation per song so a change of record is visible.
private struct WidgetRecord: View {
    let snap: WidgetSnapshot
    let item: WidgetSnapshot.Item
    let diameter: CGFloat
    let artInset: CGFloat

    var body: some View {
        MiniRecord(diameter: diameter, style: VinylStyle.at(snap.vinylIndex), art: SharedStore.coverImage(item.coverFile),
                   artIndex: item.index, artInset: artInset, ringWidth: 3, spindle: 6, sheen: false)
            .rotationEffect(.degrees(Double(item.index) * 37))
            .overlay(RecordSheen())
            .shadow(color: .black.opacity(0.5), radius: 9, x: 6, y: 8)
    }
}

/// Tonearm pivoting at the top of a box; `deg` 0 = straight down.
private struct WidgetArm: View {
    let length: CGFloat
    let head: CGSize
    let gimbal: CGFloat
    let deg: Double

    var body: some View {
        let w: CGFloat = 40, h = length + head.height + 16
        ZStack(alignment: .top) {
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: "#77777d"), Color(hex: "#f4f4f7"), Color(hex: "#8a8a90")], startPoint: .leading, endPoint: .trailing))
                .frame(width: 3, height: length)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 3, y: 4)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: "#3a3a40"))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                .frame(width: head.width, height: head.height)
                .rotationEffect(.degrees(22), anchor: .top)
                .offset(y: length - 4)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#ececf0"), Color(hex: "#8a8a90")], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: gimbal * 0.65))
                .frame(width: gimbal, height: gimbal)
                .offset(y: 8 - gimbal / 2)
        }
        .frame(width: w, height: h, alignment: .top)
        .offset(y: -8)
        .rotationEffect(.degrees(deg), anchor: UnitPoint(x: 0.5, y: 0))
        .frame(width: w, height: h, alignment: .top)
    }
}

private struct PlayPauseButton: View {
    let playing: Bool
    let size: CGFloat
    let look: WidgetLook
    var body: some View {
        Button(intent: PlayPauseIntent()) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.36, weight: .bold))
                .offset(x: playing ? 0 : 1.5)
                .foregroundStyle(look.buttonInk)
                .frame(width: size, height: size)
                .background(Circle().fill(look.button))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

private struct SkipButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    let size: CGFloat
    let look: WidgetLook
    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(look.ink2)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct Controls: View {
    let snap: WidgetSnapshot
    let look: WidgetLook
    let small: CGFloat
    let big: CGFloat
    var body: some View {
        HStack(spacing: 6) {
            SkipButton(intent: PreviousTrackIntent(), symbol: "backward.end.fill", size: small, look: look)
            PlayPauseButton(playing: snap.isPlaying, size: big, look: look)
            SkipButton(intent: NextTrackIntent(), symbol: "forward.end.fill", size: small, look: look)
        }
    }
}

// Small: record with tonearm, song below, pet in the corner. Tap the record to play or pause.
private struct SmallView: View {
    let entry: VinylEntry
    let look: WidgetLook

    var body: some View {
        let s = entry.snap
        Fit(ref: CGSize(width: 170, height: 170)) {
            ZStack(alignment: .topLeading) {
                Button(intent: PlayPauseIntent()) {
                    WidgetRecord(snap: s, item: s.current, diameter: 118, artInset: 35)
                }
                .buttonStyle(.plain)
                .offset(x: 12, y: 12)
                .id(s.current.index)
                .transition(.push(from: .trailing))
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#4a4a50"), Color(hex: "#222226")], center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 8))
                    .frame(width: 16, height: 16)
                    .offset(x: 142, y: 16)
                WidgetArm(length: 84, head: CGSize(width: 7, height: 12), gimbal: 8, deg: s.isPlaying ? 30 : 8)
                    .offset(x: 150 - 20, y: 24)
                    .animation(.spring(duration: 0.7, bounce: 0.3), value: s.isPlaying)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.current.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(look.ink)
                    Text(s.current.artist).font(.system(size: 11)).foregroundStyle(look.ink2)
                }
                .lineLimit(1)
                .frame(width: 170 - 14 - 52, alignment: .leading)
                .offset(x: 14, y: 170 - 12 - 30)
                PetSprite(pet: s.petIndex, pose: petPose(entry), pixel: 2)
                    .frame(width: 32, height: 36, alignment: .bottom)
                    .offset(x: 170 - 12 - 32, y: 170 - 12 - 36)
            }
        }
    }
}

// Medium: sleeve with the record half out of it, status, song and controls.
private struct MediumView: View {
    let entry: VinylEntry
    let look: WidgetLook

    var body: some View {
        let s = entry.snap
        Fit(ref: CGSize(width: 364, height: 170)) {
            ZStack(alignment: .topLeading) {
                Button(intent: PlayPauseIntent()) {
                    WidgetRecord(snap: s, item: s.current, diameter: 138, artInset: 44)
                }
                .buttonStyle(.plain)
                .offset(x: 76, y: 16)
                .id(s.current.index)
                .transition(.asymmetric(insertion: .offset(x: -62).combined(with: .opacity), removal: .offset(x: -62).combined(with: .opacity)))
                Sleeve(size: 138, art: SharedStore.coverImage(s.current.coverFile), artIndex: s.current.index)
                    .offset(x: 16, y: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusLine(s).uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(look.accent)
                    Text(s.current.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(look.ink)
                        .lineLimit(2)
                    Text(s.current.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(look.ink2)
                        .lineLimit(1)
                }
                .frame(width: 364 - 228 - 14, alignment: .leading)
                .offset(x: 228, y: 18)
                Controls(snap: s, look: look, small: 30, big: 38)
                    .offset(x: 222, y: 170 - 12 - 38)
            }
        }
    }
}

// Large: big sleeve and record, tonearm, pet, song, controls, progress and three records up next.
private struct LargeView: View {
    let entry: VinylEntry
    let look: WidgetLook

    var body: some View {
        let s = entry.snap
        Fit(ref: CGSize(width: 364, height: 382)) {
            ZStack(alignment: .topLeading) {
                Button(intent: PlayPauseIntent()) {
                    WidgetRecord(snap: s, item: s.current, diameter: 172, artInset: 55)
                }
                .buttonStyle(.plain)
                .offset(x: 112, y: 18)
                .id(s.current.index)
                .transition(.asymmetric(insertion: .offset(x: -94).combined(with: .opacity), removal: .offset(x: -94).combined(with: .opacity)))
                Sleeve(size: 172, art: SharedStore.coverImage(s.current.coverFile), artIndex: s.current.index, radius: 7)
                    .offset(x: 18, y: 18)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#5a5a60"), Color(hex: "#26262a")], center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 12))
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .offset(x: 322, y: 22)
                WidgetArm(length: 144, head: CGSize(width: 9, height: 16), gimbal: 12, deg: s.isPlaying ? 30 : 8)
                    .offset(x: 334 - 20, y: 34)
                    .animation(.spring(duration: 0.7, bounce: 0.3), value: s.isPlaying)
                PetSprite(pet: s.petIndex, pose: petPose(entry), pixel: 2)
                    .frame(width: 32, height: 36, alignment: .bottom)
                    .offset(x: 312, y: 155)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusLine(s).uppercased())
                            .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                            .foregroundStyle(look.accent)
                        Text(s.current.title)
                            .font(.system(size: 18, weight: .bold)).tracking(-0.18)
                            .foregroundStyle(look.ink)
                        Text(s.current.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(look.ink2)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Controls(snap: s, look: look, small: 32, big: 40)
                }
                .frame(width: 324)
                .offset(x: 20, y: 206)

                Group {
                    if s.isPlaying {
                        let start = s.updated.addingTimeInterval(-s.elapsed)
                        ProgressView(timerInterval: start...start.addingTimeInterval(max(1, s.duration)), countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                    } else {
                        ProgressView(value: min(s.elapsed, s.duration), total: max(1, s.duration))
                    }
                }
                .progressViewStyle(.linear)
                .tint(look.accent)
                .frame(width: 324)
                .offset(x: 20, y: 280)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Up next").font(.system(size: 11, weight: .semibold)).foregroundStyle(look.ink3)
                    HStack(spacing: 10) {
                        ForEach(s.upNext, id: \.index) { u in
                            HStack(spacing: 8) {
                                MiniRecord(diameter: 40, style: VinylStyle.at(s.vinylIndex), art: SharedStore.coverImage(u.coverFile),
                                           artIndex: u.index, artInset: 12, sheen: false)
                                Text(u.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(look.ink2)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(width: 324, alignment: .leading)
                .offset(x: 20, y: 300)
            }
        }
    }
}
