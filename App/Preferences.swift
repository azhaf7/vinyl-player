import SwiftUI
import ServiceManagement

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system = "System", dark = "Dark", light = "Light"
    var id: String { rawValue }
}

enum MusicSource: String, CaseIterable, Identifiable {
    case nowPlaying = "Spotify & Apple Music", samples = "Sample songs"
    var id: String { rawValue }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case desktop = "Desktop player", notch = "Notch"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .desktop: return "record.circle"
        case .notch: return "rectangle.topthird.inset.filled"
        }
    }
    var blurb: String {
        switch self {
        case .desktop: return "The full turntable on your desktop, with the pet walking over to work the tonearm."
        case .notch: return "A tiny spinning record and the pet beside the notch. Hover for the song and controls."
        }
    }
}

enum DriveChoice: String, CaseIterable, Identifiable {
    case direct = "Direct drive", belt = "Belt drive"
    var id: String { rawValue }
}

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    @Published var theme: ThemeChoice { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var sound: Bool { didSet { d.set(sound, forKey: "sound") } }
    @Published var drive: DriveChoice { didSet { d.set(drive.rawValue, forKey: "drive") } }
    @Published var armFollowsGroove: Bool { didSet { d.set(armFollowsGroove, forKey: "armFollowsGroove") } }
    @Published var petOperatesArm: Bool { didSet { d.set(petOperatesArm, forKey: "petOperatesArm") } }
    @Published var floatAboveWindows: Bool { didSet { d.set(floatAboveWindows, forKey: "floatAboveWindows") } }
    @Published var shareBaseURL: String { didSet { d.set(shareBaseURL, forKey: "shareBaseURL") } }
    @Published var senderName: String { didSet { d.set(senderName, forKey: "senderName") } }
    @Published var musicSource: MusicSource { didSet { d.set(musicSource.rawValue, forKey: "musicSource") } }
    @Published var displayMode: DisplayMode { didSet { d.set(displayMode.rawValue, forKey: "displayMode") } }
    @Published var style: PlayerStyle { didSet { d.set(try? JSONEncoder().encode(style), forKey: "playerStyle") } }
    @Published var didOnboard: Bool { didSet { d.set(didOnboard, forKey: "didOnboard") } }
    @Published var shareListening: Bool { didSet { d.set(shareListening, forKey: "shareListening") } }
    @Published var hotKeys: Bool { didSet { d.set(hotKeys, forKey: "hotKeys") } }
    @Published var showPet: Bool { didSet { d.set(showPet, forKey: "showPet") } }

    /// Where the Shared Record page (web/shared-record) is hosted.
    static let defaultShareBaseURL = "https://azhaf7.github.io/vinyl-player/shared-record/"

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: ["sound": true, "armFollowsGroove": true, "petOperatesArm": true, "floatAboveWindows": false])
        theme = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        sound = d.bool(forKey: "sound")
        drive = DriveChoice(rawValue: d.string(forKey: "drive") ?? "") ?? .direct
        armFollowsGroove = d.bool(forKey: "armFollowsGroove")
        petOperatesArm = d.bool(forKey: "petOperatesArm")
        floatAboveWindows = d.bool(forKey: "floatAboveWindows")
        shareBaseURL = d.string(forKey: "shareBaseURL") ?? Preferences.defaultShareBaseURL
        senderName = d.string(forKey: "senderName") ?? ""
        musicSource = MusicSource(rawValue: d.string(forKey: "musicSource") ?? "") ?? .nowPlaying
        displayMode = DisplayMode(rawValue: d.string(forKey: "displayMode") ?? "") ?? .desktop
        didOnboard = d.bool(forKey: "didOnboard")
        shareListening = d.object(forKey: "shareListening") as? Bool ?? true
        hotKeys = d.object(forKey: "hotKeys") as? Bool ?? true
        showPet = d.object(forKey: "showPet") as? Bool ?? true
        style = d.data(forKey: "playerStyle").flatMap { try? JSONDecoder().decode(PlayerStyle.self, from: $0) } ?? PlayerStyle()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login: \(error.localizedDescription)")
            }
        }
    }
}
