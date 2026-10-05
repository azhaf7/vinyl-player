import AppKit
import CoreServices

/// Follows whatever the Spotify or Music app on this Mac is playing, and controls it.
/// Talks to the apps with Apple Events (the user approves this once), so no account sign-in is needed.
final class NowPlayingService: PlaybackService {
    enum Source: String, CaseIterable {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"

        var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
        var appName: String { self == .spotify ? "Spotify" : "Music" }
    }

    struct Info {
        var playing: Bool
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var position: Double
        var artworkURL: String?
        var id: String
    }

    static let idleTrack = Track(title: "Play something", artist: "on Spotify or Apple Music", duration: 240, bpm: 100, tintHex: "#8a6a4a")

    let name = "Spotify & Apple Music"
    let isLive = true
    private(set) var tracks: [Track] = [NowPlayingService.idleTrack]
    private(set) var status = "Open Spotify or Apple Music and play a song." { didSet { if status != oldValue { onRemoteChange?(.status) } } }
    private(set) var needsPermission = false { didSet { if needsPermission != oldValue { onRemoteChange?(.status) } } }
    var onRemoteChange: ((RemoteChange) -> Void)?

    private var current = 0
    private var source: Source?
    private var lastID: String?
    private var lastPlaying = false
    private var connected = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var scripts: [String: NSAppleScript] = [:]
    /// The music app takes a moment to apply a command; don't trust its state until then.
    private var quietUntil = Date.distantPast
    /// Automation permission per app: nil = not asked yet, true = allowed, false = denied.
    private var allowed: [Source: Bool] = [:]
    private var asking: Set<Source> = []
    private var lastPermissionCheck = Date.distantPast
    private var lastError: String?
    /// A song id seen for the first time, and when. While another device controls Spotify over Connect,
    /// the Mac app can flick between two songs for a moment; a change only counts once it holds.
    private var candidateID: String?
    private var candidateSince = Date.distantPast

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.poll()
            })
        }
        poll()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
    }

    // MARK: Commands

    func play() { send("play") }
    func pause() { send("pause") }
    func nextTrack() { send("next track") }
    func previousTrack() { send("previous track") }

    func seek(to seconds: Double) {
        send("set player position to " + String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds))
    }

    func select(index: Int) {
        guard index != current, tracks.indices.contains(index), source == .spotify,
              let id = tracks[index].sourceID, id.hasPrefix("spotify:") else { return }
        send("play track \"\(id)\"")
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func send(_ command: String) {
        guard let source, isRunning(source), allowed[source] == true else { return }
        _ = run(cache: false, "tell application \"\(source.appName)\"\nwith timeout of 3 seconds\n\(command)\nend timeout\nend tell")
        quietUntil = Date().addingTimeInterval(1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.poll() }
    }

    // MARK: Permission

    /// Asks macOS (once) whether we may control the app. Runs off the main thread because the system
    /// prompt blocks the caller until the user answers.
    private func checkPermission(_ s: Source, ask: Bool) {
        guard !asking.contains(s) else { return }
        asking.insert(s)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let target = NSAppleEventDescriptor(bundleIdentifier: s.rawValue)
            var err: OSStatus = OSStatus(procNotFound)
            if let desc = target.aeDesc {
                err = AEDeterminePermissionToAutomateTarget(desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.asking.remove(s)
                switch Int(err) {
                case Int(noErr): self.allowed[s] = true
                case -1743, -1744: self.allowed[s] = false // errAEEventNotPermitted, errAEEventWouldRequireUserConsent
                default: break // not running, or not answered yet: try again later
                }
                self.poll()
            }
        }
    }

    // MARK: Polling

    private func isRunning(_ s: Source) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: s.rawValue).isEmpty
    }

    private func poll() {
        guard Date() >= quietUntil else { return }
        let running = Source.allCases.filter(isRunning)
        guard !running.isEmpty else {
            needsPermission = false
            status = "Open Spotify or Apple Music and play a song."
            if lastPlaying { lastPlaying = false; onRemoteChange?(.playing(false)) }
            return
        }

        // Ask for permission the first time we see each app; re-check denied ones now and then
        // (the user may have switched it on in System Settings).
        let recheck = Date().timeIntervalSince(lastPermissionCheck) > 5
        if recheck { lastPermissionCheck = Date() }
        for s in running {
            if allowed[s] == nil { checkPermission(s, ask: true) }
            else if allowed[s] == false && recheck { checkPermission(s, ask: false) }
        }

        let usable = running.filter { allowed[$0] == true }
        let denied = running.filter { allowed[$0] == false }
        var found: [(Source, Info)] = []
        for s in usable {
            if let info = query(s) { found.append((s, info)) }
        }
        let pick = found.first(where: { $0.1.playing }) ?? found.first(where: { $0.0 == source }) ?? found.first
        guard let chosen = pick else {
            if usable.isEmpty && !denied.isEmpty {
                needsPermission = true
                status = "Allow Vinyl Player to control \(denied[0].displayName): System Settings → Privacy & Security → Automation."
            } else if usable.isEmpty {
                needsPermission = false
                status = "Waiting for permission to read \(running[0].displayName)…"
            } else {
                needsPermission = false
                status = lastError ?? "\(usable[0].displayName) is open. Play a song."
            }
            if lastPlaying { lastPlaying = false; onRemoteChange?(.playing(false)) }
            return
        }
        let s = chosen.0, info = chosen.1
        source = s
        needsPermission = false
        status = "Connected to \(s.displayName)."

        if info.id == lastID { candidateID = nil }
        if info.id != lastID {
            if connected {
                if info.id != candidateID { candidateID = info.id; candidateSince = Date(); return }
                guard Date().timeIntervalSince(candidateSince) >= 0.8 else { return }
            }
            candidateID = nil
            lastID = info.id
            let t = Track(title: info.title, artist: info.artist.isEmpty ? info.album : info.artist,
                          duration: max(1, info.duration), bpm: 100, tintHex: "#8a6a4a",
                          artworkURL: info.artworkURL, sourceID: info.id, album: info.album.isEmpty ? nil : info.album)
            if !connected {
                connected = true
                tracks = [t]; current = 0
                onRemoteChange?(.reset(index: 0))
            } else {
                tracks.append(t)
                current = tracks.count - 1
                onRemoteChange?(.track(current))
            }
        }
        onRemoteChange?(.position(info.position))
        if info.playing != lastPlaying {
            lastPlaying = info.playing
            onRemoteChange?(.playing(info.playing))
        }
    }

    private func query(_ s: Source) -> Info? {
        let body: String
        switch s {
        case .spotify:
            body = """
            set vpTrack to current track
            return vpState & linefeed & (name of vpTrack) & linefeed & (artist of vpTrack) & linefeed & (album of vpTrack) & linefeed & (((duration of vpTrack) / 1000) as text) & linefeed & (player position as text) & linefeed & (artwork url of vpTrack) & linefeed & (id of vpTrack)
            """
        case .music:
            body = """
            set vpTrack to current track
            return vpState & linefeed & (name of vpTrack) & linefeed & (artist of vpTrack) & linefeed & (album of vpTrack) & linefeed & ((duration of vpTrack) as text) & linefeed & (player position as text) & linefeed & "" & linefeed & (persistent ID of vpTrack)
            """
        }
        let source = """
        tell application "\(s.appName)"
            with timeout of 2 seconds
                if player state is playing then
                    set vpState to "playing"
                else if player state is paused then
                    set vpState to "paused"
                else
                    return "stopped"
                end if
                try
                    \(body)
                on error
                    return "stopped"
                end try
            end timeout
        end tell
        """
        guard let out = run(cache: true, source), out != "stopped" else { return nil }
        let f = out.components(separatedBy: "\n")
        guard f.count >= 8 else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return Info(playing: f[0] == "playing", title: f[1], artist: f[2], album: f[3],
                    duration: num(f[4]), position: num(f[5]),
                    artworkURL: f[6].isEmpty || f[6] == "missing value" ? nil : f[6],
                    id: f[7].isEmpty ? f[1] + "|" + f[2] : f[7])
    }

    private func run(cache: Bool, _ source: String) -> String? {
        let script: NSAppleScript
        if let cached = scripts[source] {
            script = cached
        } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            if cache { scripts[source] = s }
            script = s
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            if code == -1743 || code == -1744 {
                if let s = self.source ?? Source.allCases.first(where: { source.contains("\"\($0.appName)\"") }) { allowed[s] = false }
            } else {
                NSLog("Vinyl Player: AppleScript error \(code): \(message)")
                lastError = "Couldn't read the music app (error \(code)): \(message)"
            }
            return nil
        }
        lastError = nil
        return result.stringValue
    }
}
