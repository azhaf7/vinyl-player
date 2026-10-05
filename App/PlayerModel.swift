import SwiftUI
import AppKit
import Observation

enum Drawer { case queue, records, pets, style }

/// Everything the pet view needs for one frame.
struct PetRender: Equatable {
    var x = 44.0, y = 58.0          // feet position in the column (card top is y = 58)
    var sway = 0.0, lift = 0.0, tilt = 0.0
    var sx = 1.0, sy = 1.0, face = 1.0
    var shadow = 1.0
    var pose = PetPose()
}

/// The desktop player's single source of truth. One clock (`tick`) drives all motion; nothing is restarted.
/// Ported from the prototype's Component (tick / applyArm / petTick).
@Observable
final class PlayerModel {
    // MARK: State
    private(set) var index = 0
    private(set) var playing = false
    private(set) var armOver = false
    private(set) var armLow = false
    private(set) var motor = false
    private(set) var rpm = 33
    private(set) var vinyl = 0
    private(set) var pet = 0
    var drawer: Drawer?
    var shareOpen = false
    var copied = false
    private(set) var busy = false
    private(set) var wearPhones = true
    private(set) var wearShades = true
    private(set) var wearScarf = true
    /// Total listening time; unlocks pets and accessories. Updated every few seconds.
    private(set) var listenedMinutes = 0.0
    /// Set when something new unlocks, for a moment of celebration in the crate.
    var justUnlocked: String?
    private(set) var elapsedSec = 0
    /// Bumped when the music source's track list changes.
    private(set) var tracksVersion = 0
    /// Bumped when the music source's status line changes.
    private(set) var statusVersion = 0

    // MARK: Per-frame output
    private(set) var discAngle = 0.0
    private(set) var recordY = 0.0
    private(set) var recordZ = 0.0
    private(set) var recordFlip = 0.0
    private(set) var armSwing = 3.0
    private(set) var armTilt = 3.5
    private(set) var armShadowH = 12.0
    private(set) var armShadowOpacity = 0.38
    private(set) var progress = 0.0
    private(set) var petRender = PetRender()

    // MARK: Collaborators
    @ObservationIgnored private(set) var service: PlaybackService = MockPlaybackService()
    @ObservationIgnored var onStateChange: (() -> Void)?
    let prefs = Preferences.shared
    @ObservationIgnored var hoverOn = false
    @ObservationIgnored private(set) var reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    // MARK: Internals
    @ObservationIgnored private var position = 0.0      // seconds into the track
    @ObservationIgnored private var vel = 0.0           // deg / ms
    @ObservationIgnored private var hoverZ = 0.0
    @ObservationIgnored private var recY = 0.0
    @ObservationIgnored private var recZ = 0.0
    @ObservationIgnored private var recFlip = 0.0
    @ObservationIgnored private var swing = Tween(3, duration: 850, curve: .armSwing)
    @ObservationIgnored private var lift = Tween(3.5, duration: 480, curve: .armLift)
    @ObservationIgnored private var shadowH = Tween(12, duration: 850, curve: .armSwing)
    @ObservationIgnored private var shadowOp = Tween(0.38, duration: 450, curve: .ease, jump: 0.01)
    @ObservationIgnored private var wasLow: Bool?
    @ObservationIgnored private var crackling = false
    @ObservationIgnored private var stuck = 0.0
    @ObservationIgnored private var listened = 0.0
    @ObservationIgnored private var timers: [DispatchWorkItem] = []
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private var remotePlaying: Bool?
    @ObservationIgnored private var pendingRemoteIndex: Int?

    // Pet
    private enum Mode { case home, walk, hopDown, grab, hopUp, back, swap }
    private enum Action { case play, pause, swap }
    private struct Pt { var x: Double; var y: Double }
    private static let HOME = Pt(x: 44, y: 58)
    private static let EDGE = Pt(x: 238, y: 58)
    private static let SPOT = Pt(x: 242, y: 120)
    private static let SWAP = Pt(x: 128, y: 58)
    /// Points per ms; faster than the play/pause walk (0.17) so changing songs feels snappy.
    private static let swapWalkSpeed = 0.3

    @ObservationIgnored private var pMode = Mode.home
    @ObservationIgnored private var pX = 44.0
    @ObservationIgnored private var pY = 58.0
    @ObservationIgnored private var pT = 0.0
    @ObservationIgnored private var pFace = 1.0
    @ObservationIgnored private var pDur = 1.0
    @ObservationIgnored private var pFrom = Pt(x: 44, y: 58)
    @ObservationIgnored private var pTo = Pt(x: 44, y: 58)
    @ObservationIgnored private var pAction: Action?
    @ObservationIgnored private var pTarget = 0
    @ObservationIgnored private var pFlip = false
    @ObservationIgnored private var pWasPlaying = false
    @ObservationIgnored private var pSwapped = false

    @ObservationIgnored private var amp = 0.0
    @ObservationIgnored private var beat = 0.0
    @ObservationIgnored private var clock = 0.0
    @ObservationIgnored private var blinkAt = 2000.0
    @ObservationIgnored private var lookUntil = 0.0
    @ObservationIgnored private var lookAt = 4000.0
    @ObservationIgnored private var look = 0.0
    @ObservationIgnored private var happy = 0.0
    @ObservationIgnored private var happyUntil = 0.0
    @ObservationIgnored private var hop = 0.0
    @ObservationIgnored private var hopNext = 8
    @ObservationIgnored private var pausedFor = 0.0
    @ObservationIgnored private var lid = 1.0
    @ObservationIgnored private var lastBeatInt = 0
    @ObservationIgnored private var waveUntil = 0.0

    init() {
        let d = UserDefaults.standard
        index = min(max(0, d.integer(forKey: "trackIndex")), Catalog.tracks.count - 1)
        rpm = d.integer(forKey: "rpm") == 45 ? 45 : 33
        vinyl = min(max(0, d.integer(forKey: "vinyl")), VinylStyle.all.count - 1)
        pet = min(max(0, d.integer(forKey: "pet")), PetSpec.all.count - 1)
        if d.object(forKey: "wearPhones") != nil { wearPhones = d.bool(forKey: "wearPhones") }
        if d.object(forKey: "wearShades") != nil { wearShades = d.bool(forKey: "wearShades") }
        if d.object(forKey: "wearScarf") != nil { wearScarf = d.bool(forKey: "wearScarf") }
        listened = d.double(forKey: "listenedMs")
        // Earlier versions unlocked headphones after 45 s; keep that unlock.
        if d.bool(forKey: "phonesUnlocked") { listened = max(listened, PetUnlock.headphones.minutes * 60_000) }
        listenedMinutes = listened / 60_000
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        hookService()
    }

    var tracks: [Track] { _ = tracksVersion; return service.tracks }
    var track: Track { let t = tracks; return t.indices.contains(index) ? t[index] : t[t.count - 1] }
    var isLive: Bool { service.isLive }
    var serviceStatus: String { _ = statusVersion; return service.status }
    var needsPermission: Bool { _ = statusVersion; return service.needsPermission }
    /// Live source but nothing playing yet: show the status line instead of an artist.
    var showsStatus: Bool { _ = statusVersion; return isLive && (service.needsPermission || track.sourceID == nil) }
    var side: String { isLive ? "A" : Catalog.side(of: index) }
    var duration: Double { track.duration }
    var pendingPlaying: Bool {
        switch pAction {
        case .play?: return true
        case .pause?: return false
        default: return playing
        }
    }
    var pausedSince: Date? { pendingPlaying ? nil : Date().addingTimeInterval(-pausedFor / 1000) }

    // MARK: Clock

    /// Advance everything by `rawDt` milliseconds.
    func tick(_ rawDt: Double) {
        let dt = min(64, rawDt)
        let full = Double(rpm) * 360 / 60000 * (reduced ? 0.12 : 1)
        let target = motor ? full : 0
        let belt = prefs.drive == .belt
        let tau = target > vel ? (belt ? 1500.0 : 420.0) : (belt ? 1100.0 : 380.0)
        vel = approach(vel, target, dt: dt, tau: tau)
        if !motor && vel < 1e-5 { vel = 0 }
        var angle = (discAngle + vel * dt).truncatingRemainder(dividingBy: 360)

        if motor {
            position += rawDt / 1000 * min(1, vel / full)
            if position >= duration {
                if isLive { position = duration } else { step(1) }
            }
        }

        if motor && armLow && stuck == 0 && !reduced && Double.random(in: 0..<1) < dt / 150_000 { stuck = 1500 }
        var tiltOverride: Double?
        if stuck > 0 {
            stuck -= dt
            if position > 0.4 && floor(stuck / 380) != floor((stuck + dt) / 380) { position -= 0.38 }
            angle += sin(clock / 30) * 0.6
            tiltOverride = -1.4 + abs(sin(clock / 60)) * 1.4
            if stuck <= 0 { stuck = 0; hop = 1; happyUntil = clock + 1400 }
        }
        if angle != discAngle { discAngle = angle }

        let p = min(1, max(0, position / duration))
        if p != progress { progress = p }
        let s = Int(position)
        if s != elapsedSec { elapsedSec = s }

        applyArm(p, dt: dt, tiltOverride: tiltOverride)

        let want = motor && armLow && prefs.sound
        SoundEngine.shared.enabled = prefs.sound
        if want != crackling { crackling = want; SoundEngine.shared.crackle(want) }

        if motor {
            let before = listened
            listened += dt
            if Int(listened / 5000) != Int(before / 5000) { listenedMinutes = listened / 60_000 }
            if Date().timeIntervalSince(lastSave) > 15 { save() }
        }

        petTick(dt)
        hoverZ = approach(hoverZ, hoverOn ? 2.5 : 0, dt: dt, tau: 120)
        if abs(hoverZ - (hoverOn ? 2.5 : 0)) < 0.005 { hoverZ = hoverOn ? 2.5 : 0 }
        if -recY != recordY { recordY = -recY }
        if hoverZ + recZ != recordZ { recordZ = hoverZ + recZ }
        if recFlip != recordFlip { recordFlip = recFlip }
    }

    private func applyArm(_ p: Double, dt: Double, tiltOverride: Double?) {
        let deg = armOver ? 18 + (prefs.armFollowsGroove ? 2 * p : 0) : 3
        swing.set(deg); swing.advance(dt)
        lift.set(armLow ? -1.4 : 3.5); lift.advance(dt)
        shadowH.set(armLow ? 1 : 12); shadowH.advance(dt)
        shadowOp.set(armLow ? 0.6 : 0.38); shadowOp.advance(dt)
        let tilt = tiltOverride ?? lift.value
        if swing.value != armSwing { armSwing = swing.value }
        if tilt != armTilt { armTilt = tilt }
        if shadowH.value != armShadowH { armShadowH = shadowH.value }
        if shadowOp.value != armShadowOpacity { armShadowOpacity = shadowOp.value }
        if armLow != wasLow {
            if armLow && wasLow != nil && prefs.sound { SoundEngine.shared.needleDrop() }
            wasLow = armLow
        }
    }

    // MARK: Transport

    private func later(_ ms: Double, _ fn: @escaping () -> Void) {
        let w = DispatchWorkItem(block: fn)
        timers.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000, execute: w)
    }

    private func clearTimers() { timers.forEach { $0.cancel() }; timers.removeAll() }

    /// `quick` is used after a record swap, so a song change doesn't drag.
    private func doPlay(quick: Bool = false) {
        clearTimers()
        playing = true; armOver = true
        stateChanged()
        later(quick ? 380 : 620) { [weak self] in self?.armLow = true }
        later(quick ? 600 : 980) { [weak self] in
            guard let self else { return }
            self.motor = true
            self.remotePlaying = true
            self.service.play()
            if !(self.isLive && self.track.sourceID == nil) {
                HistoryStore.shared.record(self.track, source: self.service.name)
            }
        }
    }

    private func doPause() {
        clearTimers()
        playing = false; motor = false
        remotePlaying = false
        service.pause()
        stateChanged()
        later(420) { [weak self] in self?.armLow = false }
        later(820) { [weak self] in self?.armOver = false }
    }

    private var petPerforms: Bool { prefs.petOperatesArm && !reduced }

    func toggle() {
        guard !busy else { return }
        let action: Action = playing ? .pause : .play
        guard petPerforms else { return action == .play ? doPlay() : doPause() }
        busy = true
        pAction = action
        stateChanged()
        go(.walk, Pt(x: pX, y: Self.HOME.y), Self.EDGE, abs(Self.EDGE.x - pX) / 0.17)
    }

    func next() { step(1) }
    func previous() { step(-1) }

    private func step(_ dir: Int) {
        if isLive {
            // The music app owns the queue; the record is swapped when it reports the new song.
            if dir > 0 { service.nextTrack() } else { service.previousTrack() }
            return
        }
        if dir < 0 && position > 3 { seek(fraction: 0); return }
        swapTo((index + dir + tracks.count) % tracks.count)
    }

    func swapTo(_ i: Int) {
        guard !busy, i != index else { return }
        guard petPerforms else { return pick(i) }
        pAction = .swap; pTarget = i
        pFlip = !isLive && index / 3 != i / 3 && abs(i - index) == 1
        pWasPlaying = playing; pSwapped = false
        busy = true
        if pWasPlaying {
            clearTimers()
            motor = false
            later(180) { [weak self] in self?.armLow = false }
            later(400) { [weak self] in self?.armOver = false }
        }
        go(.walk, Pt(x: pX, y: Self.HOME.y), Self.SWAP, max(150, abs(Self.SWAP.x - pX) / Self.swapWalkSpeed))
    }

    private func pick(_ i: Int) {
        position = 0; index = i; elapsedSec = 0
        service.select(index: i)
        save(); stateChanged()
        if playing && armLow {
            armLow = false
            later(900) { [weak self] in if self?.playing == true { self?.armLow = true } }
        }
    }

    func seek(fraction: Double) {
        position = min(1, max(0, fraction)) * duration
        elapsedSec = Int(position)
        service.seek(to: position)
        stateChanged()
    }

    func setRPM(_ r: Int) { rpm = r; save() }
    func selectVinyl(_ i: Int) { vinyl = i; save(); stateChanged() }
    func selectPet(_ i: Int) { guard isPetUnlocked(i) else { return }; pet = i; save(); stateChanged() }
    func toggleHeadphones() { wearPhones.toggle(); save(); stateChanged() }
    func toggleSunglasses() { wearShades.toggle(); save(); stateChanged() }
    func toggleScarf() { wearScarf.toggle(); save(); stateChanged() }

    /// The pet waves for a moment (e.g. a friend's record just arrived).
    func wave() {
        pausedFor = 0; lid = 1
        waveUntil = clock + 2400
        happyUntil = clock + 2400
    }

    // MARK: Unlocks

    // Everything is free: all pets and accessories are available from the start.
    func isUnlocked(_ u: PetUnlock) -> Bool { true }
    func isPetUnlocked(_ i: Int) -> Bool { true }
    var phonesUnlocked: Bool { isUnlocked(.headphones) }
    var headphonesOn: Bool { isUnlocked(.headphones) && wearPhones }
    var sunglassesOn: Bool { isUnlocked(.sunglasses) && wearShades }

    func petTapped() {
        pausedFor = 0; lid = 1; hop = 1; happyUntil = clock + 900
        stateChanged()
    }

    /// Apply a change that came from the music source rather than from a click here.
    func apply(_ change: RemoteChange) {
        switch change {
        case .status:
            statusVersion += 1
        case .reset(let i):
            tracksVersion += 1
            clearTimers()
            index = i; position = 0; elapsedSec = 0
            save(); stateChanged()
        case .track(let i):
            tracksVersion += 1
            if busy { pendingRemoteIndex = i } else if i != index { swapTo(i) }
        case .playing(let p):
            remotePlaying = p
            if !busy && p != pendingPlaying { toggle() }
        case .position(let s):
            // Ignore while a record swap is in progress; small differences are just clock drift.
            guard pAction != .swap, pendingRemoteIndex == nil, abs(s - position) > 1 else { return }
            position = min(duration, max(0, s))
            elapsedSec = Int(position)
        }
    }

    /// After the pet finishes, catch up with anything the music app did meanwhile.
    private func reconcile() {
        if let i = pendingRemoteIndex {
            pendingRemoteIndex = nil
            if i != index { swapTo(i); return }
        }
        if let p = remotePlaying, p != playing { toggle() }
    }

    /// Switch music source (e.g. to Spotify once signed in).
    func use(_ newService: PlaybackService) {
        service.stop()
        service.onRemoteChange = nil
        clearTimers()
        if playing { playing = false; motor = false; armLow = false; armOver = false }
        busy = false; pAction = nil; pMode = .home; pX = Self.HOME.x; pY = Self.HOME.y
        remotePlaying = nil; pendingRemoteIndex = nil
        service = newService
        tracksVersion += 1
        index = isLive ? 0 : min(max(0, UserDefaults.standard.integer(forKey: "trackIndex")), tracks.count - 1)
        position = 0; elapsedSec = 0
        hookService()
        service.start()
        stateChanged()
    }

    private func hookService() {
        service.onRemoteChange = { [weak self] change in DispatchQueue.main.async { self?.apply(change) } }
    }

    // MARK: Pet

    private func go(_ mode: Mode, _ from: Pt, _ to: Pt, _ dur: Double) {
        pMode = mode; pFrom = from; pTo = to; pDur = max(1, dur); pT = 0
        if to.x != from.x { pFace = to.x > from.x ? 1 : -1 }
    }

    private func petTick(_ dt: Double) {
        let isPlaying = playing, PI = Double.pi
        clock += dt
        var legs = PetLegs.stand, arms = PetArms.down, liftY = 0.0
        var forceEyes: PetEyes? = nil

        switch pMode {
        case .home:
            break
        case .swap:
            pT += dt; arms = .up; forceEyes = .look
            let D = pWasPlaying ? 520.0 : 80.0, OUT = 440.0, GAP = 100.0, IN = 480.0
            let u = min(1, max(0, (pT - D) / OUT)), v = min(1, max(0, (pT - D - OUT - GAP) / IN))
            if pT < D { arms = .down; forceEyes = nil }
            if u >= 1 && !pSwapped {
                pSwapped = true
                position = 0; index = pTarget; elapsedSec = 0
                service.select(index: pTarget)
                save(); stateChanged()
            }
            let yOut = u * u * (3 - 2 * u), yIn = 1 - pow(1 - v, 3)
            recY = pFlip ? 0 : (pSwapped ? 300 * (1 - yIn) : 300 * yOut)
            recZ = sin((pSwapped ? 1 - v : u) * PI / 2) * (pFlip ? 46 : 36)
            recFlip = pFlip ? (pSwapped ? -90 * (1 - yIn) : 90 * yOut) : 0
            liftY = (u > 0 && u < 1 ? sin(u * PI) * 5 : 0) + (v > 0 && v < 1 ? sin(v * PI) * 3 : 0)
            if v >= 1 {
                recY = 0; recZ = 0; recFlip = 0
                if pWasPlaying { doPlay(quick: true) }
                go(.back, Pt(x: pX, y: pY), Self.HOME, max(150, abs(pX - Self.HOME.x) / Self.swapWalkSpeed))
            }
        case .grab:
            pT += dt; arms = .up; forceEyes = .look
            liftY = max(0, sin(min(1, pT / 700) * PI)) * 2
            if pT > 1150 { go(.hopUp, Self.SPOT, Self.EDGE, 460) }
        case .walk, .hopDown, .hopUp, .back:
            pT = min(1, pT + dt / pDur)
            let walking = pMode == .walk || pMode == .back
            let k = walking ? pT : (1 - cos(pT * PI)) / 2
            pX = pFrom.x + (pTo.x - pFrom.x) * k
            pY = pFrom.y + (pTo.y - pFrom.y) * k
            if walking {
                legs = Int(clock / 130) % 2 == 1 ? .a : .b
                liftY = abs(sin(clock / 130 * PI)) * 1.5
            } else {
                liftY = sin(pT * PI) * 16; arms = .up
            }
            if pT >= 1 {
                switch pMode {
                case .walk:
                    if pAction == .swap { pMode = .swap; pT = 0; pFace = 1 } else { go(.hopDown, Self.EDGE, Self.SPOT, 460) }
                case .hopDown:
                    pMode = .grab; pT = 0; pFace = 1
                    if pAction == .play { doPlay() } else { doPause() }
                case .hopUp:
                    go(.back, Pt(x: pX, y: pY), Self.HOME, max(200, abs(pX - Self.HOME.x) / 0.17))
                case .back:
                    recY = 0; recZ = 0; pMode = .home; pFace = 1; pAction = nil
                    busy = false
                    stateChanged()
                    if isLive { reconcile() }
                default: break
                }
            }
        }

        let atHome = pMode == .home
        let bpm = track.bpm
        amp = approach(amp, isPlaying && atHome ? (reduced ? 0.15 : 1) : 0, dt: dt, tau: isPlaying ? 260 : 160)
        if amp > 0.002 { beat += dt / 1000 * (bpm / 60) }
        let b = beat, a = amp
        let bi = Int(floor(b))
        if bi != lastBeatInt {
            lastBeatInt = bi
            if isPlaying && atHome && !reduced {
                hopNext -= 1
                if hopNext <= 0 { hop = 1; hopNext = 6 + Int.random(in: 0..<8) }
            }
            if isPlaying && Double.random(in: 0..<1) < 0.08 { happyUntil = clock + 1400 }
        }
        hop = max(0, hop - dt / 420)
        let tempo = min(1, max(0, (bpm - 84) / 34))
        let bounce = pow(abs(sin(b * PI)), 1.4) * (1.6 + 4 * tempo) * a + sin(hop * PI) * 6
        let sway = (sin(b * PI / 2) * (3.2 - 1.8 * tempo) + sin(b * PI * 0.37) * 0.7) * a
        let tilt = sin(b * PI / 2 + 0.4) * 2 * a
        let land = pow(1 - abs(sin(b * PI)), 6) * a
        let breathe = atHome ? sin(clock / 1600 * PI) * (1 - a) : 0
        let sy = 1 - land * 0.05 + breathe * 0.015, sx = 1 + land * 0.04 - breathe * 0.006

        if clock > lookAt { lookUntil = clock + 1200 + Double.random(in: 0..<900); lookAt = lookUntil + 3500 + Double.random(in: 0..<5000) }
        look = approach(look, clock < lookUntil ? 1 : 0, dt: dt, tau: 180)
        let wasAsleep = pausedFor > 20_000
        pausedFor = isPlaying || !atHome ? 0 : pausedFor + dt
        if (pausedFor > 20_000) != wasAsleep { stateChanged() }
        lid = approach(lid, pausedFor > 7000 ? 0.45 : 1, dt: dt, tau: pausedFor > 7000 ? 900 : 90)
        var blink = 1.0
        if clock > blinkAt {
            let q = (clock - blinkAt) / 150
            if q >= 1 { blinkAt = clock + 2200 + Double.random(in: 0..<3200) } else { blink = 0.1 }
        }
        happy = approach(happy, isPlaying && atHome && clock < happyUntil ? 1 : 0, dt: dt, tau: 120)
        if atHome && a > 0.5 && !reduced && bi % 2 == 0 { arms = .up }
        if atHome && clock < waveUntil {
            arms = Int(clock / 200) % 2 == 0 ? .up : .down
            forceEyes = .happy
        }
        let eyes: PetEyes = pausedFor > 20_000 ? .sleep
            : min(blink, lid) < 0.5 ? .blink
            : forceEyes ?? (happy > 0.5 ? .happy : look > 0.5 ? .look : .open)

        var r = PetRender()
        r.x = pX; r.y = pY
        r.sway = sway; r.lift = bounce + liftY; r.tilt = tilt
        r.sx = sx; r.sy = sy; r.face = pFace
        r.shadow = max(0.4, 1 - (bounce + liftY) / 30)
        r.pose = PetPose(arms: arms, eyes: eyes, legs: legs, headphones: headphonesOn, sunglasses: sunglassesOn,
                         scarf: wearScarf ? ArtworkService.shared.tint(for: track) : nil)
        if r != petRender { petRender = r }
    }

    // MARK: Share

    func shareURL() -> URL? {
        func enc(_ s: String) -> String {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        let from = prefs.senderName.trimmingCharacters(in: .whitespaces).isEmpty ? "A friend" : prefs.senderName
        var fields = [("song", track.title), ("by", track.artist), ("from", from), ("pet", PetSpec.at(pet).name)]
        // From Spotify: link the exact track, not a search.
        if let id = track.sourceID, id.hasPrefix("spotify:track:") {
            fields.append(("spotify", String(id.dropFirst("spotify:track:".count))))
        }
        let frag = fields
            .map { $0.0 + "=" + enc($0.1) }.joined(separator: "&")
        var base = prefs.shareBaseURL.trimmingCharacters(in: .whitespaces)
        if let hash = base.firstIndex(of: "#") { base = String(base[..<hash]) }
        return URL(string: base + "#" + frag)
    }

    func copyShareLink() {
        guard let url = shareURL() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copied = true
    }

    // MARK: Persistence

    private func stateChanged() { onStateChange?() }

    private func save() {
        let d = UserDefaults.standard
        if !isLive { d.set(index, forKey: "trackIndex") }
        d.set(rpm, forKey: "rpm")
        d.set(vinyl, forKey: "vinyl"); d.set(pet, forKey: "pet")
        d.set(wearPhones, forKey: "wearPhones"); d.set(wearShades, forKey: "wearShades"); d.set(wearScarf, forKey: "wearScarf")
        d.set(listened, forKey: "listenedMs")
        lastSave = Date()
    }
}
