import AppIntents
import WidgetKit

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Lowers or lifts the tonearm.")
    func perform() async throws -> some IntentResult {
        WidgetActions.run(.playPause)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Song"
    func perform() async throws -> some IntentResult {
        WidgetActions.run(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Song"
    func perform() async throws -> some IntentResult {
        WidgetActions.run(.previous)
        return .result()
    }
}

/// Sends the press to the app (which runs the pet sequence and writes the real state), and updates the
/// snapshot right away so the widget responds instantly. Without the app running it acts on the snapshot alone.
enum WidgetActions {
    static func run(_ cmd: WidgetCommand) {
        let running = SharedStore.hostIsRunning
        if running { SharedStore.enqueue(cmd) }
        var s = SharedStore.readSnapshot() ?? .placeholder
        let now = Date()
        switch cmd {
        case .playPause:
            if s.isPlaying {
                s.elapsed = s.elapsed(at: now); s.isPlaying = false; s.pausedSince = now
            } else {
                s.isPlaying = true; s.pausedSince = nil
            }
        case .next, .previous:
            if running || s.live == true { return } // the app (or the music app) changes the song itself
            let n = Catalog.tracks.count
            let known: [Int: WidgetSnapshot.Item] = Dictionary(([s.current] + s.upNext).map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
            func item(_ i: Int) -> WidgetSnapshot.Item {
                known[i] ?? .init(title: Catalog.tracks[i].title, artist: Catalog.tracks[i].artist, index: i, coverFile: nil)
            }
            let i = (s.current.index + (cmd == .next ? 1 : n - 1)) % n
            s.current = item(i)
            s.upNext = (1...3).map { item((i + $0) % n) }
            s.elapsed = 0; s.duration = Catalog.tracks[i].duration
            s.tintHex = Catalog.tracks[i].tintHex
            s.side = Catalog.side(of: i)
        }
        s.updated = now
        SharedStore.writeSnapshot(s)
    }
}
