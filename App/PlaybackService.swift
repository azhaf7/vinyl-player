import Foundation

/// The seam for real music sources (Spotify, Apple Music). The player animates first and then calls these,
/// e.g. `play()` is sent at the moment the motor starts, as in the design.
protocol PlaybackService: AnyObject {
    var name: String { get }
    var tracks: [Track] { get }
    func play()
    func pause()
    func select(index: Int)
    func seek(to seconds: Double)
    /// Remote changes (paused from the phone, next song...) are reported here; the player runs the
    /// same pet sequence it would for a local press.
    var onRemoteChange: ((RemoteChange) -> Void)? { get set }
}

enum RemoteChange {
    case playing(Bool)
    case track(Int)
    case position(Double)
}

/// Plays nothing: time is simulated by the player. Used until a real source is connected.
final class MockPlaybackService: PlaybackService {
    let name = "Sample songs"
    let tracks = Catalog.tracks
    var onRemoteChange: ((RemoteChange) -> Void)?

    func play() {}
    func pause() {}
    func select(index: Int) {}
    func seek(to seconds: Double) {}
}
