import Foundation

/// One play of a song.
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var artist: String
    var artworkURL: String?
    var spotifyID: String?
    var source: String
    var playedAt: Date
    var duration: Double? = nil
    var album: String? = nil

    var track: Track {
        Track(title: title, artist: artist, duration: duration ?? 240, bpm: 100, tintHex: "#8a6a4a",
              artworkURL: artworkURL, sourceID: spotifyID.map { "spotify:track:" + $0 }, album: album)
    }
}

/// Songs you've played, newest first, saved in Application Support.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []
    private let url: URL
    private let limit = 2000

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VinylPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let saved = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = saved
        }
    }

    /// Called when the motor starts on a song. Replaying the same song within 10 minutes isn't a new entry.
    static func entry(for track: Track, source: String) -> HistoryEntry {
        let spotify = track.sourceID.flatMap { $0.hasPrefix("spotify:track:") ? String($0.dropFirst("spotify:track:".count)) : nil }
        return HistoryEntry(title: track.title, artist: track.artist, artworkURL: track.artworkURL,
                            spotifyID: spotify, source: source, playedAt: Date(), duration: track.duration, album: track.album)
    }

    func record(_ track: Track, source: String) {
        if let last = entries.first, last.title == track.title, last.artist == track.artist,
           Date().timeIntervalSince(last.playedAt) < 600 { return }
        entries.insert(Self.entry(for: track, source: source), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    struct TopSong: Identifiable {
        let entry: HistoryEntry
        let plays: Int
        var id: UUID { entry.id }
    }

    /// Most played songs, for the "Top songs" list.
    var topSongs: [TopSong] {
        var counts: [String: (HistoryEntry, Int)] = [:]
        for e in entries {
            let key = (e.title + "|" + e.artist).lowercased()
            counts[key] = (counts[key]?.0 ?? e, (counts[key]?.1 ?? 0) + 1)
        }
        return counts.values.sorted { $0.1 > $1.1 }.prefix(20).map { TopSong(entry: $0.0, plays: $0.1) }
    }

    /// Plays in the last 7 days, for the weekly recap.
    var thisWeek: [HistoryEntry] {
        let since = Date().addingTimeInterval(-7 * 24 * 3600)
        return entries.filter { $0.playedAt >= since }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}
