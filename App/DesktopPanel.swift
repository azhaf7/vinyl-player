import AppKit
import SwiftUI
import QuartzCore

/// Borderless, transparent window pinned to the desktop (behind normal windows), or floating when the
/// user prefers. This is the full-animation "widget".
final class DesktopPanel: NSPanel {
    convenience init(contentRect: NSRect) {
        self.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // drawn in SwiftUI
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: Drag from anywhere

    /// Areas (content coordinates, y down) where a drag keeps its own meaning, e.g. scrubbing.
    var noDragRects: [CGRect] = []

    private var dragDown: NSEvent?
    private var dragMouse = NSPoint.zero
    private var dragOrigin = NSPoint.zero
    private var moving = false

    /// A press that moves more than a few points moves the window, wherever it started.
    /// A press that doesn't move stays a normal click (play, buttons, the pet...).
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            moving = false
            let p = contentView.map { $0.convert(event.locationInWindow, from: nil) } ?? event.locationInWindow
            dragDown = noDragRects.contains(where: { $0.contains(p) }) ? nil : event
            dragMouse = NSEvent.mouseLocation
            dragOrigin = frame.origin
            super.sendEvent(event)
        case .leftMouseDragged:
            if let down = dragDown {
                let m = NSEvent.mouseLocation
                let dx = m.x - dragMouse.x, dy = m.y - dragMouse.y
                if !moving && hypot(dx, dy) > 4 {
                    moving = true
                    // Cancel whatever the press started (a tap, a button) with a release far outside.
                    if let cancel = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000),
                                                       modifierFlags: [], timestamp: event.timestamp, windowNumber: windowNumber,
                                                       context: nil, eventNumber: down.eventNumber, clickCount: 1, pressure: 0) {
                        super.sendEvent(cancel)
                    }
                }
                if moving {
                    setFrameOrigin(NSPoint(x: dragOrigin.x + dx, y: dragOrigin.y + dy))
                    return
                }
            }
            super.sendEvent(event)
        case .leftMouseUp:
            dragDown = nil
            if moving { moving = false; return }
            super.sendEvent(event)
        default:
            super.sendEvent(event)
        }
    }

    func applyLevel(floating: Bool) {
        level = floating ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
}

final class DesktopPanelController: NSObject, NSWindowDelegate {
    private let model: PlayerModel
    private var panel: DesktopPanel?
    private let driver: FrameDriver

    /// Room around the 344-wide column for the card's shadow; height leaves space for the panels below.
    static let margin: CGFloat = 40
    static let size = NSSize(width: 344 + 2 * margin, height: margin + 58 + 384 + 12 + 230 + margin)

    init(model: PlayerModel) {
        self.model = model
        driver = FrameDriver { [weak model] dt in model?.tick(dt) }
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil { build() }
        panel?.orderFrontRegardless()
        driver.setFast(true)
    }

    func hide() {
        panel?.orderOut(nil)
        driver.setFast(false)
    }

    func toggle() { isVisible ? hide() : show() }

    func resetPosition() {
        guard let panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - Self.size.width - 24, y: f.maxY - Self.size.height - 8))
    }

    func applyLevel() { panel?.applyLevel(floating: Preferences.shared.floatAboveWindows) }

    private func build() {
        let p = DesktopPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        let root = PlayerRoot(model: model)
            .padding(Self.margin)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: Self.size)
        p.contentView = host
        p.delegate = self
        p.applyLevel(floating: Preferences.shared.floatAboveWindows)
        // The progress bar (card x 22, y 302, 300 × 18) keeps dragging for scrubbing.
        p.noDragRects = [CGRect(x: Self.margin + 18, y: Self.margin + 58 + 296, width: 308, height: 30)]
        panel = p
        if let saved = UserDefaults.standard.string(forKey: "panelOrigin") {
            p.setFrameOrigin(NSPointFromString(saved))
        } else {
            resetPosition()
        }
        driver.attach(to: host)
    }

    func windowDidMove(_ notification: Notification) {
        guard let p = panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "panelOrigin")
    }

    /// Full frame rate only while someone can see it; otherwise a slow tick keeps playback time moving.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let p = panel else { return }
        driver.setFast(p.occlusionState.contains(.visible))
    }
}

/// One clock for all motion: the display's refresh when visible, a 4 Hz timer when hidden.
final class FrameDriver: NSObject {
    private let onTick: (Double) -> Void
    private var link: CADisplayLink?
    private var slow: Timer?
    private var last = CACurrentMediaTime()

    init(onTick: @escaping (Double) -> Void) {
        self.onTick = onTick
        super.init()
        setFast(false)
    }

    func attach(to view: NSView) {
        link?.invalidate()
        let l = view.displayLink(target: self, selector: #selector(frame(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        setFast(true)
    }

    func setFast(_ fast: Bool) {
        if let link {
            link.isPaused = !fast
        }
        let wantSlow = !fast || link == nil
        if wantSlow, slow == nil {
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.step() }
            RunLoop.main.add(t, forMode: .common)
            slow = t
        } else if !wantSlow {
            slow?.invalidate(); slow = nil
        }
        last = CACurrentMediaTime()
    }

    @objc private func frame(_ l: CADisplayLink) { step() }

    private func step() {
        let now = CACurrentMediaTime()
        let dt = (now - last) * 1000
        last = now
        if dt > 0 { onTick(dt) }
    }
}

/// `NSVisualEffectView` (.hudWindow) behind the glass.
struct VisualEffectBlur: NSViewRepresentable {
    var radius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.maskImage = Self.mask(radius)
        return v
    }

    /// Stretchable rounded-rect mask so the blur never shows past the card's corners.
    static func mask(_ r: CGFloat) -> NSImage? {
        guard r > 0 else { return nil }
        let side = r * 2 + 1
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

