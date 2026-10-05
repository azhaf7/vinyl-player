import Foundation

/// A record that arrived as a link (Messages, AirDrop, mail…). Kept so it can be opened again from the
/// Library, with or without accounts.
struct SavedRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var record: SharedRecord
    var receivedAt: Date
}

final class LinkInbox: ObservableObject {
    static let shared = LinkInbox()

    @Published private(set) var records: [SavedRecord] = []
    private let url: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VinylPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("link-inbox.json")
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let saved = try? d.decode([SavedRecord].self, from: data) { records = saved }
    }

    /// Adds the record unless the same song from the same person is already the newest one.
    func add(_ record: SharedRecord) {
        if let first = records.first, first.record == record { return }
        records.insert(SavedRecord(record: record, receivedAt: Date()), at: 0)
        if records.count > 300 { records.removeLast(records.count - 300) }
        save()
    }

    func remove(_ item: SavedRecord) {
        records.removeAll { $0.id == item.id }
        save()
    }

    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(records) { try? data.write(to: url, options: .atomic) }
    }
}
