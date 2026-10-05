import Foundation
import AppKit

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String
    var displayName: String?
    var pet: String?

    var name: String { displayName?.isEmpty == false ? displayName! : "@" + username }
}

/// A record someone sent.
struct Share: Codable, Identifiable, Hashable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    var title: String
    var artist: String
    var spotifyId: String?
    var artworkUrl: String?
    var message: String?
    var pet: String?
    var createdAt: Date
    var openedAt: Date?
    var sender: Profile?
    var recipient: Profile?

    var track: Track {
        Track(title: title, artist: artist, duration: 240, bpm: 100, tintHex: "#8a6a4a",
              artworkURL: artworkUrl, sourceID: spotifyId.map { "spotify:track:" + $0 })
    }
}

struct SocialError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Accounts, friends and in-app sharing, on Supabase (auth + PostgREST over plain HTTPS).
/// No login: each Mac quietly gets an anonymous account with a friend code (e.g. @mochi4821) the
/// first time it runs. Friends add each other's code, then records go straight to each other's inbox.
final class SocialService: ObservableObject {
    static let shared = SocialService()

    enum State: Equatable {
        case notConfigured
        case signedOut
        case needsUsername
        case signedIn(Profile)
    }

    @Published private(set) var state: State = SocialConfig.isConfigured ? .signedOut : .notConfigured
    @Published private(set) var friends: [Profile] = []
    @Published private(set) var inbox: [Share] = []
    @Published private(set) var sent: [Share] = []

    /// Called with records that arrived since the last check.
    var onNewShares: (([Share]) -> Void)?
    /// Why automatic setup failed, if it did (shown with a Retry button).
    @Published private(set) var setupError: String?
    private var petName = "mochi"
    private var settingUp = false

    var me: Profile? { if case .signedIn(let p) = state { return p } else { return nil } }
    var unopenedCount: Int { inbox.filter { $0.openedAt == nil }.count }

    private struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: UUID
    }

    private var session: Session?
    private var timer: Timer?
    private var knownInbox: Set<UUID> = []
    private let sessionURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VinylPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sessionURL = dir.appendingPathComponent("session.json")
    }

    // MARK: Lifecycle

    func start(petName: String) {
        guard SocialConfig.isConfigured else { return }
        self.petName = petName
        if let data = try? Data(contentsOf: sessionURL), let s = try? JSONDecoder().decode(Session.self, from: data) {
            session = s
            loadProfile()
        } else {
            setUp()
        }
        if timer == nil {
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    /// Creates this Mac's account and friend code, without asking anything. Retries a taken code.
    func setUp(attempt: Int = 0) {
        guard SocialConfig.isConfigured, me == nil, !settingUp || attempt > 0 else { return }
        settingUp = true
        setupError = nil
        let base = petName.lowercased().filter { $0.isLetter }.prefix(10)
        let code = (base.isEmpty ? "vinyl" : String(base)) + String(Int.random(in: 1000...9999))
        claim(username: code, displayName: Preferences.shared.senderName, pet: petName) { [weak self] err in
            guard let self else { return }
            if let err {
                if err.contains("taken") && attempt < 4 { self.setUp(attempt: attempt + 1); return }
                self.setupError = err
            }
            self.settingUp = false
        }
    }

    /// Change the friend code to something nicer (optional).
    func rename(to raw: String, completion: @escaping (String?) -> Void) {
        guard let me else { completion("Not set up yet."); return }
        let username = raw.lowercased().replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces)
        guard username.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            completion("Use 3–20 letters, numbers or _."); return
        }
        call("PATCH", "/rest/v1/profiles", query: [URLQueryItem(name: "id", value: "eq." + me.id.uuidString.lowercased())],
             json: ["username": username], prefer: "return=representation") { [weak self] result in
            switch result {
            case .success(let data):
                if let p = (try? Self.decoder.decode([Profile].self, from: data))?.first { self?.state = .signedIn(p) }
                completion(nil)
            case .failure(let e):
                completion(e.message.contains("23505") || e.message.contains("duplicate") ? "@\(username) is taken." : e.message)
            }
        }
    }

    /// Re-fetch friends and records.
    func refresh() {
        guard me != nil else { return }
        loadFriends()
        loadInbox()
        loadSent()
    }

    // MARK: Account

    /// Creates the account (first time) and claims `username`.
    func claim(username raw: String, displayName: String, pet: String, completion: @escaping (String?) -> Void) {
        let username = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard username.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            completion("Use 3–20 letters, numbers or _ for your username."); return
        }
        let create = { [weak self] in
            guard let self, let s = self.session else { completion("Couldn't create your account."); return }
            let body: [String: Any] = ["id": s.userID.uuidString.lowercased(), "username": username,
                                       "display_name": displayName.trimmingCharacters(in: .whitespaces), "pet": pet]
            self.call("POST", "/rest/v1/profiles", json: body, prefer: "return=representation") { result in
                switch result {
                case .success(let data):
                    if let p = (try? Self.decoder.decode([Profile].self, from: data))?.first {
                        self.state = .signedIn(p); self.refresh(); completion(nil)
                    } else { completion("Couldn't save your profile.") }
                case .failure(let e):
                    completion(e.message.contains("duplicate") || e.message.contains("23505") ? "@\(username) is taken. Try another." : e.message)
                }
            }
        }
        if session != nil { create(); return }
        // Anonymous sign-up: an account without email or password, kept on this Mac.
        call("POST", "/auth/v1/signup", json: [:], authed: false) { [weak self] result in
            switch result {
            case .success(let data):
                guard let self, let s = Self.session(from: data) else { completion("Couldn't create your account."); return }
                self.session = s; self.saveSession(); create()
            case .failure(let e):
                completion(e.message.contains("disabled") ? "Anonymous sign-ins are off in Supabase (see README)." : e.message)
            }
        }
    }

    func updateProfile(displayName: String, pet: String) {
        guard let me else { return }
        call("PATCH", "/rest/v1/profiles", query: [URLQueryItem(name: "id", value: "eq." + me.id.uuidString.lowercased())],
             json: ["display_name": displayName, "pet": pet], prefer: "return=representation") { [weak self] result in
            if case .success(let data) = result, let p = (try? Self.decoder.decode([Profile].self, from: data))?.first {
                self?.state = .signedIn(p)
            }
        }
    }

    /// Forgets this Mac's session. The account can't be recovered afterwards (it has no email).
    func signOut() {
        session = nil
        try? FileManager.default.removeItem(at: sessionURL)
        friends = []; inbox = []; sent = []; knownInbox = []
        state = SocialConfig.isConfigured ? .signedOut : .notConfigured
    }

    private func loadProfile() {
        guard let s = session else { return }
        call("GET", "/rest/v1/profiles", query: [URLQueryItem(name: "id", value: "eq." + s.userID.uuidString.lowercased()),
                                                URLQueryItem(name: "select", value: "id,username,display_name,pet")]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                if let p = (try? Self.decoder.decode([Profile].self, from: data))?.first {
                    self.state = .signedIn(p); self.refresh()
                } else {
                    self.state = .needsUsername
                    self.setUp()
                }
            case .failure:
                break // offline: try again on the next refresh
            }
        }
    }

    // MARK: Friends

    func find(username raw: String, completion: @escaping (Profile?) -> Void) {
        let username = raw.lowercased().replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces)
        guard !username.isEmpty else { completion(nil); return }
        call("GET", "/rest/v1/profiles", query: [URLQueryItem(name: "username", value: "eq." + username),
                                                URLQueryItem(name: "select", value: "id,username,display_name,pet")]) { result in
            if case .success(let data) = result { completion((try? Self.decoder.decode([Profile].self, from: data))?.first) }
            else { completion(nil) }
        }
    }

    func addFriend(_ p: Profile) {
        guard let me, p.id != me.id else { return }
        call("POST", "/rest/v1/friendships", json: ["user_id": me.id.uuidString.lowercased(), "friend_id": p.id.uuidString.lowercased()],
             prefer: "resolution=ignore-duplicates") { [weak self] _ in self?.loadFriends() }
    }

    func removeFriend(_ p: Profile) {
        guard let me else { return }
        call("DELETE", "/rest/v1/friendships", query: [URLQueryItem(name: "user_id", value: "eq." + me.id.uuidString.lowercased()),
                                                       URLQueryItem(name: "friend_id", value: "eq." + p.id.uuidString.lowercased())]) { [weak self] _ in
            self?.loadFriends()
        }
    }

    private struct FriendRow: Codable { var friend: Profile?; var user: Profile? }

    /// People you added and people who added you.
    private func loadFriends() {
        guard let me else { return }
        let id = me.id.uuidString.lowercased()
        call("GET", "/rest/v1/friendships", query: [
            URLQueryItem(name: "or", value: "(user_id.eq.\(id),friend_id.eq.\(id))"),
            URLQueryItem(name: "select", value: "friend:profiles!friendships_friend_id_fkey(id,username,display_name,pet),user:profiles!friendships_user_id_fkey(id,username,display_name,pet)"),
        ]) { [weak self] result in
            guard case .success(let data) = result, let rows = try? Self.decoder.decode([FriendRow].self, from: data) else { return }
            var seen = Set<UUID>(), list: [Profile] = []
            for r in rows {
                for p in [r.friend, r.user].compactMap({ $0 }) where p.id != me.id && !seen.contains(p.id) {
                    seen.insert(p.id); list.append(p)
                }
            }
            self?.friends = list.sorted { $0.username < $1.username }
        }
    }

    // MARK: Records

    func send(_ track: Track, to friend: Profile, message: String, pet: String, completion: @escaping (String?) -> Void) {
        guard me != nil else { completion("Create your username first."); return }
        var body: [String: Any] = ["recipient_id": friend.id.uuidString.lowercased(), "title": track.title, "artist": track.artist, "pet": pet]
        if let id = track.sourceID, id.hasPrefix("spotify:track:") { body["spotify_id"] = String(id.dropFirst("spotify:track:".count)) }
        if let art = track.artworkURL, art.hasPrefix("https://") { body["artwork_url"] = art }
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { body["message"] = String(note.prefix(140)) }
        call("POST", "/rest/v1/shares", json: body) { [weak self] result in
            switch result {
            case .success: self?.loadSent(); completion(nil)
            case .failure(let e): completion(e.message)
            }
        }
    }

    func markOpened(_ share: Share) {
        guard share.openedAt == nil else { return }
        if let i = inbox.firstIndex(where: { $0.id == share.id }) { inbox[i].openedAt = Date() }
        call("PATCH", "/rest/v1/shares", query: [URLQueryItem(name: "id", value: "eq." + share.id.uuidString.lowercased())],
             json: ["opened_at": ISO8601DateFormatter().string(from: Date())]) { _ in }
    }

    func delete(_ share: Share) {
        inbox.removeAll { $0.id == share.id }
        sent.removeAll { $0.id == share.id }
        call("DELETE", "/rest/v1/shares", query: [URLQueryItem(name: "id", value: "eq." + share.id.uuidString.lowercased())]) { _ in }
    }

    private static let shareSelect = "*,sender:profiles!shares_sender_id_fkey(id,username,display_name,pet),recipient:profiles!shares_recipient_id_fkey(id,username,display_name,pet)"

    private func loadInbox() {
        guard let me else { return }
        call("GET", "/rest/v1/shares", query: [URLQueryItem(name: "recipient_id", value: "eq." + me.id.uuidString.lowercased()),
                                              URLQueryItem(name: "order", value: "created_at.desc"),
                                              URLQueryItem(name: "limit", value: "100"),
                                              URLQueryItem(name: "select", value: Self.shareSelect)]) { [weak self] result in
            guard let self, case .success(let data) = result, let list = try? Self.decoder.decode([Share].self, from: data) else { return }
            let firstLoad = self.knownInbox.isEmpty && self.inbox.isEmpty
            let fresh = list.filter { !self.knownInbox.contains($0.id) && $0.openedAt == nil }
            self.knownInbox.formUnion(list.map(\.id))
            self.inbox = list
            if !firstLoad && !fresh.isEmpty { self.onNewShares?(fresh) }
        }
    }

    private func loadSent() {
        guard let me else { return }
        call("GET", "/rest/v1/shares", query: [URLQueryItem(name: "sender_id", value: "eq." + me.id.uuidString.lowercased()),
                                              URLQueryItem(name: "order", value: "created_at.desc"),
                                              URLQueryItem(name: "limit", value: "100"),
                                              URLQueryItem(name: "select", value: Self.shareSelect)]) { [weak self] result in
            guard case .success(let data) = result, let list = try? Self.decoder.decode([Share].self, from: data) else { return }
            self?.sent = list
        }
    }

    // MARK: HTTP

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    /// Postgres timestamps have up to 6 fractional digits; trim to 3 for ISO8601DateFormatter.
    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let pattern = "(\\.[0-9]{3})[0-9]+"
        let trimmed = s.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        if let d = f.date(from: trimmed) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: trimmed)
    }

    private static func session(from data: Data) -> Session? {
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = object as? [String: Any] else { return nil }
        guard let access = json["access_token"] as? String else { return nil }
        guard let refreshToken = json["refresh_token"] as? String else { return nil }
        guard let user = json["user"] as? [String: Any], let idString = user["id"] as? String else { return nil }
        guard let id = UUID(uuidString: idString) else { return nil }
        let expiresIn = json["expires_in"] as? Double ?? 3600
        return Session(accessToken: access, refreshToken: refreshToken, expiresAt: Date().addingTimeInterval(expiresIn), userID: id)
    }

    private func saveSession() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: sessionURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionURL.path)
    }

    /// Makes sure the access token is fresh, then runs `body` on the main queue.
    private func withFreshToken(_ body: @escaping (String?) -> Void) {
        guard let s = session else { body(nil); return }
        guard s.expiresAt.timeIntervalSinceNow < 120 else { body(s.accessToken); return }
        var req = URLRequest(url: URL(string: SocialConfig.supabaseURL + "/auth/v1/token?grant_type=refresh_token")!)
        req.httpMethod = "POST"
        req.setValue(SocialConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if let data, code == 200, let fresh = Self.session(from: data) {
                    self.session = fresh; self.saveSession(); body(fresh.accessToken)
                } else if code == 400 || code == 401 {
                    // The session is gone on the server; start over.
                    self.signOut(); body(nil)
                } else {
                    body(s.accessToken) // offline: try with what we have
                }
            }
        }.resume()
    }

    private func call(_ method: String, _ path: String, query: [URLQueryItem] = [], json: [String: Any]? = nil,
                      prefer: String? = nil, authed: Bool = true, completion: @escaping (Result<Data, SocialError>) -> Void) {
        guard SocialConfig.isConfigured, var comps = URLComponents(string: SocialConfig.supabaseURL + path) else {
            completion(.failure(SocialError(message: "Sharing isn't set up."))); return
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { completion(.failure(SocialError(message: "Bad request."))); return }
        let run = { (token: String?) in
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue(SocialConfig.anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer " + (token ?? SocialConfig.anonKey), forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
            if let json { req.httpBody = try? JSONSerialization.data(withJSONObject: json) }
            URLSession.shared.dataTask(with: req) { data, response, error in
                DispatchQueue.main.async {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if let data, (200..<300).contains(code) {
                        completion(.success(data))
                    } else {
                        var message = error?.localizedDescription ?? "Request failed (\(code))."
                        if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let parts = [obj["code"], obj["message"], obj["msg"], obj["error_description"]].compactMap { $0.map { "\($0)" } }
                            if !parts.isEmpty { message = parts.joined(separator: ": ") }
                        }
                        completion(.failure(SocialError(message: message)))
                    }
                }
            }.resume()
        }
        if authed { withFreshToken(run) } else { run(nil) }
    }
}
