import Foundation
import Combine
import WidgetKit

/// Keeps the widgets in sync: writes snapshots (throttled to once a second), reloads timelines, answers
/// widget button presses, and keeps a heartbeat so widgets know whether the app is running.
final class WidgetBridge {
    private let model: PlayerModel
    private let artwork = ArtworkService.shared
    private var pending = false
    private var lastWrite = Date.distantPast
    private var lastSnapshot: WidgetSnapshot?
    private var heartbeat: Timer?
    private var bag = Set<AnyCancellable>()

    init(model: PlayerModel) {
        self.model = model
        model.onStateChange = { [weak self] in self?.schedule() }
        artwork.$revision.dropFirst().sink { [weak self] _ in self?.schedule() }.store(in: &bag)

        SharedStore.beat()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in SharedStore.beat() }

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let bridge = Unmanaged<WidgetBridge>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { bridge.handleCommands() }
        }, SharedStore.commandNotification as CFString, nil, .deliverImmediately)

        _ = SharedStore.takeCommands() // ignore presses from before launch
        schedule()
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }

    func handleCommands() {
        for cmd in SharedStore.takeCommands() {
            switch cmd {
            case .playPause: model.toggle()
            case .next: model.next()
            case .previous: model.previous()
            }
        }
        schedule()
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        let wait = max(0, 1 - Date().timeIntervalSince(lastWrite))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.write() }
    }

    private func write() {
        pending = false
        lastWrite = Date()
        let tracks = model.tracks
        func item(_ i: Int) -> WidgetSnapshot.Item {
            let t = tracks[i]
            _ = artwork.image(for: t) // starts a lookup if needed
            return .init(title: t.title, artist: t.artist, index: i, coverFile: artwork.coverFile(for: t))
        }
        let upNext = (1...3).map { item((model.index + $0) % tracks.count) }
        let snap = WidgetSnapshot(current: item(model.index), upNext: upNext,
                                  tintHex: artwork.tint(for: model.track).hex,
                                  isPlaying: model.pendingPlaying,
                                  elapsed: Double(model.elapsedSec), duration: model.duration,
                                  side: model.side, petIndex: model.pet, vinylIndex: model.vinyl,
                                  headphones: model.phonesUnlocked && model.wearPhones,
                                  updated: Date(), pausedSince: model.pausedSince)
        if let last = lastSnapshot, Self.same(last, snap) { return }
        lastSnapshot = snap
        SharedStore.writeSnapshot(snap)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
    }

    /// Ignore changes that are only the clock moving on.
    private static func same(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
        var a = a
        let drift = abs(b.elapsed(at: b.updated) - a.elapsed(at: b.updated))
        let samePause = (a.pausedSince == nil) == (b.pausedSince == nil)
        a.updated = b.updated; a.elapsed = b.elapsed; a.pausedSince = b.pausedSince
        return a == b && drift < 3 && samePause
    }
}
