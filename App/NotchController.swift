import SwiftUI
import AppKit

/// Geometry and hover state shared between the notch window and its view.
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var notchWidth: CGFloat = 180
    @Published var notchHeight: CGFloat = 32
    @Published var hasNotch = false

    static let wing: CGFloat = 44
    static let expandedExtra: CGFloat = 136
    static let expandedMinWidth: CGFloat = 440

    var collapsedSize: CGSize { CGSize(width: notchWidth + 2 * Self.wing, height: notchHeight) }
    var expandedSize: CGSize {
        CGSize(width: max(Self.expandedMinWidth, notchWidth + 2 * Self.wing), height: notchHeight + Self.expandedExtra)
    }
}

/// A small player living in the MacBook notch (or a notch-shaped pill at the top of screens without one):
/// a spinning record on the left, the pet on the right, and song info and controls on hover.
final class NotchController {
    private let model: PlayerModel
    private let state = NotchState()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?

    init(model: PlayerModel) { self.model = model }

    /// True when the built-in display has a notch; used for the default setting.
    static var screenHasNotch: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil { build() }
        layout()
        panel?.orderFrontRegardless()
        FrameDriver.shared.want(true, for: "notch")
        if monitors.isEmpty {
            if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in self?.track() }) {
                monitors.append(g)
            }
            if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] e in self?.track(); return e }) {
                monitors.append(l)
            }
        }
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in self?.layout() }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        FrameDriver.shared.want(false, for: "notch")
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
    }

    private var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func build() {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView: NotchView(model: model, state: state))
        panel = p
    }

    /// The window always has the expanded size, anchored to the top centre; the view draws the
    /// current (collapsed or expanded) shape inside it.
    private func layout() {
        guard let screen, let panel else { return }
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            state.hasNotch = true
            state.notchWidth = screen.frame.width - left.width - right.width
            state.notchHeight = screen.safeAreaInsets.top
        } else {
            state.hasNotch = false
            state.notchWidth = 160
            state.notchHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        }
        let size = state.expandedSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func currentRect() -> NSRect? {
        guard let screen else { return nil }
        let size = state.expanded ? state.expandedSize : state.collapsedSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Expand when the pointer reaches the notch; collapse when it leaves the expanded shape.
    private func track() {
        guard let rect = currentRect() else { return }
        let inside = rect.insetBy(dx: state.expanded ? -8 : 0, dy: state.expanded ? -8 : 0).contains(NSEvent.mouseLocation)
        if inside != state.expanded {
            state.expanded = inside
            panel?.ignoresMouseEvents = !inside
        }
    }
}

/// Black notch shape with square top corners and rounded bottom corners.
private struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                               topTrailingRadius: 0, style: .continuous).path(in: rect)
    }
}

struct NotchView: View {
    let model: PlayerModel
    @ObservedObject var state: NotchState
    @ObservedObject private var artwork = ArtworkService.shared

    var body: some View {
        let _ = artwork.revision
        let art = artwork.image(for: model.track)
        let tint = artwork.tint(for: model.track)
        let size = state.expanded ? state.expandedSize : state.collapsedSize

        ZStack(alignment: .top) {
            NotchShape(radius: state.expanded ? 24 : 10)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)

            VStack(spacing: 0) {
                // Top row: record on the left wing, pet on the right wing, the real notch in between.
                HStack(spacing: 0) {
                    NotchRecord(model: model, art: art, size: min(22, state.notchHeight - 8))
                        .frame(width: NotchState.wing, alignment: .center)
                        .opacity(state.expanded ? 0 : 1)
                    Spacer(minLength: state.notchWidth)
                    NotchPet(model: model, maxHeight: state.notchHeight - 4)
                        .frame(width: NotchState.wing, alignment: .center)
                }
                .frame(width: size.width, height: state.notchHeight)

                if state.expanded {
                    NotchDetails(model: model, art: art, tint: tint)
                        .frame(width: size.width - 32)
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(NotchShape(radius: state.expanded ? 24 : 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: state.expanded)
        .environment(\.colorScheme, .dark)
    }
}

private struct NotchRecord: View {
    let model: PlayerModel
    let art: NSImage?
    let size: CGFloat

    var body: some View {
        MiniRecord(diameter: size, style: VinylStyle.at(model.vinyl), art: art, artIndex: model.index,
                   artInset: size * 0.2, spindle: 2, sheen: false)
            .rotationEffect(.degrees(model.discAngle))
            .overlay(RecordSheen())
    }
}

private struct NotchPet: View {
    let model: PlayerModel
    let maxHeight: CGFloat

    var body: some View {
        let r = model.petRender
        let rows = CGFloat(PetSpriteCache.rows(pet: model.pet))
        let pixel = max(1, min(1.5, maxHeight / rows))
        PetSprite(pet: model.pet, pose: r.pose, pixel: pixel)
            .scaleEffect(x: r.sx, y: r.sy, anchor: .bottom)
            .rotationEffect(.degrees(r.tilt), anchor: .bottom)
            .offset(x: r.sway * 0.4, y: -min(4, r.lift * 0.4))
            .frame(height: maxHeight, alignment: .bottom)
    }
}

private struct NotchDetails: View {
    let model: PlayerModel
    let art: NSImage?
    let tint: RGB

    var body: some View {
        let ink = Ink(dark: true)
        HStack(spacing: 16) {
            // The record itself, big, with the album art on its label, spinning with the turntable.
            MiniRecord(diameter: 104, style: VinylStyle.at(model.vinyl), art: art, artIndex: model.index,
                       artInset: 22, ringWidth: 3, spindle: 5, sheen: false)
                .rotationEffect(.degrees(model.discAngle))
                .overlay(RecordSheen())
                .shadow(color: tint.opacity(0.35).color, radius: 14)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink.ink)
                    Text(model.showsStatus ? model.serviceStatus : model.track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(ink.ink2)
                    if let album = model.track.album, !model.showsStatus {
                        Text(album)
                            .font(.system(size: 11))
                            .foregroundStyle(ink.ink3)
                    }
                }
                .lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(tint.mix(.white, 0.8).color).frame(width: g.size.width * model.progress)
                    }
                }
                .frame(height: 3)
                HStack(spacing: 2) {
                    IconButton(symbol: "backward.end.fill", size: 30, ink: ink) { model.previous() }
                    Button { model.toggle() } label: {
                        Image(systemName: model.pendingPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressStyle())
                    IconButton(symbol: "forward.end.fill", size: 30, ink: ink) { model.next() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
