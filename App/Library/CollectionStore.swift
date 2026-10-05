import Foundation

struct Playlist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var songs: [HistoryEntry] = []
    var created = Date()
}

/// Liked songs and your own playlists, saved in Application Support.
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    @Published private(set) var liked: [HistoryEntry] = []
    @Published private(set) var playlists: [Playlist] = []
    private let url: URL

    private struct Saved: Codable {
        var liked: [HistoryEntry]
        var playlists: [Playlist]
    }

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VinylPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("collection.json")
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let s = try? d.decode(Saved.self, from: data) {
            liked = s.liked; playlists = s.playlists
        }
    }

    static func key(_ title: String, _ artist: String) -> String { (title + "|" + artist).lowercased() }

    // MARK: Likes

    func isLiked(_ track: Track) -> Bool { liked.contains { Self.key($0.title, $0.artist) == track.key } }

    func toggleLike(_ track: Track) {
        if isLiked(track) {
            liked.removeAll { Self.key($0.title, $0.artist) == track.key }
        } else {
            liked.insert(HistoryStore.entry(for: track, source: "Liked"), at: 0)
        }
        save()
    }

    func unlike(_ entry: HistoryEntry) {
        liked.removeAll { Self.key($0.title, $0.artist) == Self.key(entry.title, entry.artist) }
        save()
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(_ name: String) -> Playlist {
        let p = Playlist(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "New Playlist" : name)
        playlists.insert(p, at: 0)
        save()
        return p
    }

    func rename(_ p: Playlist, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == p.id }) else { return }
        playlists[i].name = name
        save()
    }

    func delete(_ p: Playlist) {
        playlists.removeAll { $0.id == p.id }
        save()
    }

    func add(_ entry: HistoryEntry, to p: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == p.id }) else { return }
        var e = entry
        e.id = UUID()
        playlists[i].songs.append(e)
        save()
    }

    func remove(_ entry: HistoryEntry, from p: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == p.id }) else { return }
        playlists[i].songs.removeAll { $0.id == entry.id }
        save()
    }

    func move(in p: Playlist, from: IndexSet, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == p.id }) else { return }
        playlists[i].songs.move(fromOffsets: from, toOffset: to)
        save()
    }

    func playlist(_ id: UUID) -> Playlist? { playlists.first { $0.id == id } }

    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(Saved(liked: liked, playlists: playlists)) { try? data.write(to: url, options: .atomic) }
    }
}
