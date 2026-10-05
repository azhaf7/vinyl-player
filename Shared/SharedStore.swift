import Foundation
import AppKit

/// What the widgets show. The app writes it on every state change (throttled); widgets only read it.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        var title: String
        var artist: String
        var index: Int
        var coverFile: String?
    }

    var current: Item
    var upNext: [Item]
    var tintHex: String
    var isPlaying: Bool
    var elapsed: Double
    var duration: Double
    var side: String
    var petIndex: Int
    var vinylIndex: Int
    var headphones: Bool
    var updated: Date
    var pausedSince: Date?

    var tint: RGB { RGB(hex: tintHex) }

    /// Shown before the app has ever run.
    static var placeholder: WidgetSnapshot {
        let items = Catalog.tracks.enumerated().map { Item(title: $1.title, artist: $1.artist, index: $0, coverFile: nil) }
        return WidgetSnapshot(current: items[0], upNext: Array(items[1...3]), tintHex: Catalog.tracks[0].tintHex,
                              isPlaying: false, elapsed: 0, duration: Catalog.tracks[0].duration, side: "A",
                              petIndex: 0, vinylIndex: 0, headphones: false, updated: Date(), pausedSince: nil)
    }

    /// Elapsed time now, assuming playback continued since the snapshot was written.
    func elapsed(at date: Date) -> Double {
        guard isPlaying else { return elapsed }
        return min(duration, elapsed + date.timeIntervalSince(updated))
    }
}

enum WidgetCommand: String, Codable {
    case playPause, next, previous
}

/// The App Group shared by the host app and the widget extension.
enum SharedStore {
    static let widgetKind = "VinylWidget"
    static let commandNotification = "com.azhaf7.vinylplayer.command"

    /// `$(TeamIdentifierPrefix)vinylplayer`, expanded at build time into both Info.plists.
    static let groupID: String? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "VinylAppGroup") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }()

    static let defaults: UserDefaults = {
        if let id = groupID, let d = UserDefaults(suiteName: id) { return d }
        return .standard
    }()

    /// Folder for shared files (covers). Falls back to Application Support when no App Group is available.
    static let containerURL: URL = {
        if let id = groupID, let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VinylPlayer", isDirectory: true)
    }()

    static var coversURL: URL {
        let url = containerURL.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Snapshot

    private static let snapshotKey = "widgetSnapshot"

    static func readSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func writeSnapshot(_ snap: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snap) { defaults.set(data, forKey: snapshotKey) }
    }

    static func coverImage(_ file: String?) -> NSImage? {
        guard let file else { return nil }
        return NSImage(contentsOf: coversURL.appendingPathComponent(file))
    }

    // MARK: Host heartbeat

    private static let heartbeatKey = "hostHeartbeat"

    static func beat() { defaults.set(Date().timeIntervalSince1970, forKey: heartbeatKey) }

    static var hostIsRunning: Bool {
        Date().timeIntervalSince1970 - defaults.double(forKey: heartbeatKey) < 12
    }

    // MARK: Commands (widget → app)

    private static let commandsKey = "pendingCommands"

    static func enqueue(_ cmd: WidgetCommand) {
        var list = defaults.stringArray(forKey: commandsKey) ?? []
        list.append(cmd.rawValue)
        defaults.set(list, forKey: commandsKey)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(commandNotification as CFString), nil, nil, true)
    }

    static func takeCommands() -> [WidgetCommand] {
        let list = defaults.stringArray(forKey: commandsKey) ?? []
        if !list.isEmpty { defaults.removeObject(forKey: commandsKey) }
        return list.compactMap(WidgetCommand.init(rawValue:))
    }
}
