import Foundation

/// The seam for music sources. The player animates first and then calls these,
/// e.g. `play()` is sent at the moment the motor starts, as in the design.
protocol PlaybackService: AnyObject {
    var name: String { get }
    /// Songs the player knows about. Never empty.
    var tracks: [Track] { get }
    /// True when the music comes from another app: it owns the queue, so next / previous are sent to it
    /// and the record is swapped when it reports the new song.
    var isLive: Bool { get }
    /// Short line for Settings, e.g. "Connected to Spotify".
    var status: String { get }
    func play()
    func pause()
    func nextTrack()
    func previousTrack()
    /// The player switched to `index` (after the swap animation, or a pick in the crate).
    func select(index: Int)
    func seek(to seconds: Double)
    /// Changes made in the music app (paused from the keyboard, next song...). The player runs the
    /// same pet sequence it would for a local press.
    var onRemoteChange: ((RemoteChange) -> Void)? { get set }
    func start()
    func stop()
}

enum RemoteChange {
    case playing(Bool)
    case track(Int)
    case position(Double)
    /// The track list was replaced (first contact with the source): jump to `index` without animating.
    case reset(index: Int)
}

/// Six built-in songs; time is simulated by the player.
final class MockPlaybackService: PlaybackService {
    let name = "Sample songs"
    let tracks = Catalog.tracks
    let isLive = false
    let status = "Playing the six built-in sample songs."
    var onRemoteChange: ((RemoteChange) -> Void)?

    func play() {}
    func pause() {}
    func nextTrack() {}
    func previousTrack() {}
    func select(index: Int) {}
    func seek(to seconds: Double) {}
    func start() {}
    func stop() {}
}
