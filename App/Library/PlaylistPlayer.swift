import Foundation

/// Plays one of your playlists in order. With Spotify, each song is started in the Spotify app and the
/// turntable follows it; with the sample songs, the record is swapped. When a song finishes, the next one
/// starts. Changing songs yourself ends the playlist.
final class PlaylistPlayer: ObservableObject {
    static let shared = PlaylistPlayer()

    @Published private(set) var playlist: Playlist?
    @Published private(set) var position = 0
    weak var model: PlayerModel?

    private var timer: Timer?
    private var expected: String?
    private var matched = false
    private var startedAt = Date()
    private var lastProgress = 0.0

    var current: HistoryEntry? {
        guard let p = playlist, p.songs.indices.contains(position) else { return nil }
        return p.songs[position]
    }

    func play(_ p: Playlist, from index: Int = 0) {
        guard !p.songs.isEmpty else { return }
        playlist = p
        start(min(max(0, index), p.songs.count - 1))
        if timer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        playlist = nil; expected = nil
    }

    func skip() {
        guard let p = playlist else { return }
        position + 1 < p.songs.count ? start(position + 1) : stop()
    }

    private func start(_ i: Int) {
        guard let model, let p = playlist, p.songs.indices.contains(i) else { stop(); return }
        position = i
        let e = p.songs[i]
        expected = CollectionStore.key(e.title, e.artist)
        matched = false
        lastProgress = 0
        startedAt = Date()
        if model.isLive {
            if e.spotifyID != nil {
                Spotify.play(id: e.spotifyID, title: e.title, artist: e.artist)
            } else {
                skip() // can't start a song without a Spotify id
            }
        } else if let idx = model.tracks.firstIndex(where: { $0.key == expected }) {
            if idx != model.index { model.swapTo(idx) }
            if !model.pendingPlaying { model.toggle() }
        } else {
            skip()
        }
    }

    private func check() {
        guard let model, playlist != nil, let expected else { return }
        if model.track.key == expected {
            matched = true
            lastProgress = model.progress
            return
        }
        if !matched {
            // Still switching (the pet may be busy): retry the sample-song swap, give up after a while.
            if Date().timeIntervalSince(startedAt) > 12 { skip() }
            else if !model.isLive, let idx = model.tracks.firstIndex(where: { $0.key == expected }), !model.busy {
                model.swapTo(idx)
            }
            return
        }
        // The song changed: if ours had (almost) finished, play the next; otherwise the user took over.
        if lastProgress > 0.85 { skip() } else { stop() }
    }
}
