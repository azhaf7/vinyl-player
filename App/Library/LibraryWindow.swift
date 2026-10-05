import SwiftUI
import AppKit

enum LibrarySection: String, CaseIterable, Identifiable {
    case inbox = "Inbox", history = "History", friends = "Friends", account = "Account"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .inbox: return "tray.and.arrow.down"
        case .history: return "clock.arrow.circlepath"
        case .friends: return "person.2"
        case .account: return "person.crop.circle"
        }
    }
}

enum OpenRecord {
    case share(Share)
    case link(SavedRecord)
}

final class LibraryNavigation: ObservableObject {
    @Published var section: LibrarySection? = .inbox
    @Published var open: OpenRecord?
}

final class LibraryWindowController {
    static let shared = LibraryWindowController()
    let nav = LibraryNavigation()
    private var window: NSWindow?
    var model: PlayerModel?

    func show(_ section: LibrarySection? = nil, share: Share? = nil) {
        if let section { nav.section = section }
        if let share { nav.section = .inbox; nav.open = .share(share) }
        if window == nil, let model {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Vinyl Library"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 820, height: 620)
            w.contentView = NSHostingView(rootView: LibraryView(model: model, nav: nav))
            w.center()
            w.setFrameAutosaveName("VinylLibrary")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct LibraryView: View {
    let model: PlayerModel
    @ObservedObject var nav: LibraryNavigation
    @ObservedObject private var social = SocialService.shared

    var body: some View {
        NavigationSplitView {
            List(LibrarySection.allCases, selection: $nav.section) { s in
                Label(s.rawValue, systemImage: s.symbol)
                    .badge(s == .inbox ? social.unopenedCount : 0)
                    .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch nav.section ?? .inbox {
                case .inbox: InboxView(model: model, nav: nav)
                case .history: HistoryView(model: model)
                case .friends: FriendsView(model: model)
                case .account: AccountView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { social.refresh() }
    }
}

// MARK: - Shared bits

/// Album art for any track, loaded through the artwork cache.
struct TrackArt: View {
    let track: Track
    var size: CGFloat = 44
    var radius: CGFloat = 6
    @ObservedObject private var artwork = ArtworkService.shared

    var body: some View {
        let _ = artwork.revision
        CoverArt(image: artwork.image(for: track), index: track.key.utf8.reduce(0) { ($0 + Int($1)) % 6 })
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// "Send to…" menu listing friends.
struct SendMenu: View {
    let track: Track
    let model: PlayerModel
    @ObservedObject private var social = SocialService.shared
    @State private var result: String?

    var body: some View {
        Menu {
            if social.me == nil {
                Button("Setting up sharing…") {}.disabled(true)
            } else if social.friends.isEmpty {
                Button("Add friends first…") { LibraryWindowController.shared.show(.friends) }
            } else {
                ForEach(social.friends) { f in
                    Button(f.name + "  @" + f.username) {
                        social.send(track, to: f, message: "", pet: PetSpec.at(model.pet).name) { err in
                            result = err ?? "Sent to @\(f.username)"
                        }
                    }
                }
            }
        } label: {
            Label(result ?? "Send", systemImage: result == nil ? "paperplane" : "checkmark")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

enum Spotify {
    /// Plays the song in the Spotify app (the turntable follows it), or opens it on the web.
    static func play(id: String?, title: String, artist: String) {
        if let id, NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil {
            let script = NSAppleScript(source: "tell application \"Spotify\" to play track \"spotify:track:\(id)\"")
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            if error == nil { return }
            if let url = URL(string: "spotify:track:" + id) { NSWorkspace.shared.open(url); return }
        }
        let q = (title + " " + artist).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil, let url = URL(string: "spotify:search:" + q) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: id.map { "https://open.spotify.com/track/" + $0 } ?? "https://open.spotify.com/search/" + q) {
            NSWorkspace.shared.open(url)
        }
    }
}

private func relative(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

struct NotSetUpView: View {
    var body: some View {
        ContentUnavailableView {
            Label("In-app sharing isn't switched on", systemImage: "person.2.slash")
        } description: {
            Text("You can still share records as links: use Share… in the player's share panel. To send records straight to friends' inboxes, set up Supabase as described in the README (Accounts and sharing).")
        }
    }
}

/// Shown while this Mac's friend code is being created.
struct SettingUpView: View {
    @ObservedObject private var social = SocialService.shared
    var body: some View {
        VStack(spacing: 12) {
            if let err = social.setupError {
                Text("Couldn't set up sharing").font(.headline)
                Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                Button("Try Again") { social.setUp() }
            } else {
                ProgressView()
                Text("Setting up sharing…").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inbox

private struct InboxView: View {
    let model: PlayerModel
    @ObservedObject var nav: LibraryNavigation
    @ObservedObject private var social = SocialService.shared
    @ObservedObject private var links = LinkInbox.shared
    @State private var tab = 0

    var body: some View {
        if let open = nav.open {
            VStack(spacing: 0) {
                HStack {
                    Button { nav.open = nil } label: { Label("Inbox", systemImage: "chevron.left") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(12)
                switch open {
                case .share(let share):
                    SharedRecordView(record: SharedRecord(share: share))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { social.markOpened(share) }
                case .link(let saved):
                    SharedRecordView(record: saved.record)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(hex: "#121013"))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Received").tag(0)
                    Text("Sent").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .padding(16)
                if tab == 0 { received } else { sentList }
            }
        }
    }

    @ViewBuilder private var received: some View {
        if social.inbox.isEmpty && links.records.isEmpty {
            ContentUnavailableView("No records yet", systemImage: "opticaldisc",
                                   description: Text("Records friends send you arrive here sealed. Links you open are kept here too."))
        } else {
            List {
                if !social.inbox.isEmpty {
                    Section("From friends") {
                        ForEach(social.inbox) { s in
                            ShareRow(share: s, received: true)
                                .contentShape(Rectangle())
                                .onTapGesture { nav.open = .share(s) }
                                .contextMenu {
                                    Button("Play on My Turntable") { Spotify.play(id: s.spotifyId, title: s.title, artist: s.artist) }
                                    Button("Delete", role: .destructive) { social.delete(s) }
                                }
                        }
                    }
                }
                if !links.records.isEmpty {
                    Section("From links") {
                        ForEach(links.records) { r in
                            HStack(spacing: 12) {
                                TrackArt(track: r.record.track, size: 52)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.record.title).font(.headline)
                                    Text(r.record.artist).foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("from " + r.record.from).font(.callout)
                                    Text(relative(r.receivedAt)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture { nav.open = .link(r) }
                            .contextMenu {
                                Button("Play on My Turntable") { Spotify.play(id: r.record.spotifyID, title: r.record.title, artist: r.record.artist) }
                                Button("Delete", role: .destructive) { links.remove(r) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var sentList: some View {
        if social.sent.isEmpty {
            ContentUnavailableView("Nothing sent yet", systemImage: "paperplane",
                                   description: Text("Send a song from the player's share panel, History or Friends."))
        } else {
            List(social.sent) { s in
                ShareRow(share: s, received: false)
                    .contextMenu { Button("Delete", role: .destructive) { social.delete(s) } }
            }
        }
    }
}

private struct ShareRow: View {
    let share: Share
    let received: Bool

    var body: some View {
        let sealed = received && share.openedAt == nil
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                TrackArt(track: share.track, size: 52)
                    .blur(radius: sealed ? 6 : 0)
                    .overlay(sealed ? RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.15)) : nil)
                if sealed {
                    Circle().fill(Tokens.accent.color).frame(width: 10, height: 10).offset(x: 3, y: -3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(sealed ? "A sealed record" : share.title).font(.headline)
                Text(sealed ? "Open it to see the song" : share.artist).foregroundStyle(.secondary)
                if let m = share.message, !m.isEmpty, !sealed { Text("“\(m)”").font(.callout).italic() }
            }
            .lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                let who = received ? share.sender : share.recipient
                Text((received ? "from " : "to ") + (who.map { "@" + $0.username } ?? "someone"))
                    .font(.callout)
                Text(relative(share.createdAt)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - History

private struct HistoryView: View {
    let model: PlayerModel
    @ObservedObject private var history = HistoryStore.shared
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text("Recent").tag(0)
                    Text("Top songs").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
                Text("\(history.entries.count) plays").foregroundStyle(.secondary)
            }
            .padding(16)
            if history.entries.isEmpty {
                ContentUnavailableView("No songs yet", systemImage: "clock",
                                       description: Text("Songs you play on the turntable show up here."))
            } else if tab == 0 {
                List(history.entries) { e in
                    HistoryRow(entry: e, detail: relative(e.playedAt), model: model)
                        .contextMenu { Button("Remove from History", role: .destructive) { history.remove(e) } }
                }
            } else {
                List(history.topSongs) { item in
                    HistoryRow(entry: item.entry, detail: "\(item.plays) play" + (item.plays == 1 ? "" : "s"), model: model)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let detail: String
    let model: PlayerModel

    var body: some View {
        HStack(spacing: 12) {
            TrackArt(track: entry.track, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.headline)
                Text(entry.artist).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Button { Spotify.play(id: entry.spotifyID, title: entry.title, artist: entry.artist) } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Play in Spotify")
            SendMenu(track: entry.track, model: model)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Friends

private struct FriendsView: View {
    let model: PlayerModel
    @ObservedObject private var social = SocialService.shared
    @State private var query = ""
    @State private var found: Profile?
    @State private var note: String?

    var body: some View {
        switch social.state {
        case .notConfigured: NotSetUpView()
        case .signedOut, .needsUsername: SettingUpView()
        case .signedIn(let me):
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Your friend code is **@\(me.username)**. Give it to friends so they can add you.")
                        .foregroundStyle(.secondary)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("@" + me.username, forType: .string)
                    }
                }
                HStack {
                    TextField("Add a friend by their code, e.g. @mochi4821", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(search)
                    Button("Find", action: search).disabled(query.isEmpty)
                }
                .frame(maxWidth: 420)
                if let found {
                    HStack {
                        PetSprite(pet: PetSpec.all.firstIndex(where: { $0.name == found.pet }) ?? 0, pose: PetPose(), pixel: 2)
                        Text(found.name + "  @" + found.username)
                        Spacer()
                        Button(social.friends.contains(found) ? "Added" : "Add friend") { social.addFriend(found) }
                            .disabled(social.friends.contains(found))
                    }
                    .frame(maxWidth: 420)
                } else if let note {
                    Text(note).foregroundStyle(.secondary)
                }
                Divider()
                if social.friends.isEmpty {
                    ContentUnavailableView("No friends yet", systemImage: "person.2", description: Text("Add someone by their username to send them records."))
                } else {
                    List(social.friends) { f in
                        HStack(spacing: 12) {
                            PetSprite(pet: PetSpec.all.firstIndex(where: { $0.name == f.pet }) ?? 0, pose: PetPose(), pixel: 2)
                                .frame(width: 32)
                            VStack(alignment: .leading) {
                                Text(f.name).font(.headline)
                                Text("@" + f.username).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Send “\(model.track.title)”") {
                                social.send(model.track, to: f, message: "", pet: PetSpec.at(model.pet).name) { err in
                                    note = err ?? "Sent “\(model.track.title)” to @\(f.username)."
                                }
                            }
                            .disabled(model.isLive && model.track.sourceID == nil)
                        }
                        .contextMenu { Button("Remove Friend", role: .destructive) { social.removeFriend(f) } }
                    }
                }
            }
            .padding(20)
        }
    }

    private func search() {
        note = nil; found = nil
        social.find(username: query) { p in
            found = p
            if p == nil { note = "No one called @\(query.lowercased().replacingOccurrences(of: "@", with: ""))." }
        }
    }
}

// MARK: - Account

struct AccountView: View {
    let model: PlayerModel
    @ObservedObject private var social = SocialService.shared
    @State private var code = ""
    @State private var displayName = ""
    @State private var note: String?

    var body: some View {
        switch social.state {
        case .notConfigured:
            NotSetUpView()
        case .signedOut, .needsUsername:
            SettingUpView()
        case .signedIn(let me):
            Form {
                Section {
                    LabeledContent("Friend code", value: "@" + me.username)
                    HStack {
                        TextField("Change code", text: $code, prompt: Text(me.username))
                        Button("Save") {
                            social.rename(to: code) { err in note = err ?? "Saved." }
                        }
                        .disabled(code.isEmpty)
                    }
                    TextField("Your name (shown to friends)", text: $displayName)
                        .onAppear { displayName = me.displayName ?? "" }
                        .onSubmit { social.updateProfile(displayName: displayName, pet: PetSpec.at(model.pet).name) }
                    LabeledContent("Pet", value: PetSpec.at(model.pet).name)
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("No login needed: this Mac has its own friend code. Friends add your code once, then records go straight to each other's inbox.")
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 520)
        }
    }
}

// MARK: - Welcome

final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    func show(model: PlayerModel) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView(model: model) { [weak self] in self?.window?.close() })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let model: PlayerModel
    let done: () -> Void
    @ObservedObject private var prefs = Preferences.shared
    @State private var step = 0

    var body: some View {
        VStack(spacing: 22) {
            PetSprite(pet: model.pet, pose: PetPose(arms: .up, eyes: .happy), pixel: 4)
            if step == 0 {
                Text("Where should your turntable live?").font(.title.bold())
                HStack(spacing: 14) {
                    ForEach(DisplayMode.allCases) { m in
                        VStack(spacing: 10) {
                            Image(systemName: m.symbol).font(.system(size: 34))
                            Text(m.rawValue).font(.headline)
                            Text(m.blurb).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .frame(width: 180, height: 170)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(prefs.displayMode == m ? 0.1 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(prefs.displayMode == m ? Tokens.accent.color : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                        .onTapGesture { prefs.displayMode = m }
                    }
                }
                Text("You can change this anytime from the menu bar.").font(.callout).foregroundStyle(.secondary)
                Button("Start listening") { finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 640, height: 520)
    }

    private func finish() {
        prefs.didOnboard = true
        done()
    }
}
