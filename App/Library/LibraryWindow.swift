import SwiftUI
import AppKit

/// Three places, each with a few pages picked at the top.
enum LibrarySection: String, CaseIterable, Identifiable {
    case collection = "Collection", history = "History", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .collection: return "square.stack"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

/// What you chose to keep: songs you liked, your playlists, the crate to flip through, and records
/// people sent you as links.
enum CollectionPage: String, CaseIterable, Identifiable {
    case liked = "Liked", playlists = "Playlists", crate = "Crate", received = "Received"
    var id: String { rawValue }
}

/// What you played, automatically: every song, and your week in numbers.
enum HistoryPage: String, CaseIterable, Identifiable {
    case played = "Played", recap = "Weekly Recap"
    var id: String { rawValue }
}

final class LibraryNavigation: ObservableObject {
    @Published var section: LibrarySection? = .collection
    @Published var collectionPage: CollectionPage = .liked
    @Published var historyPage: HistoryPage = .played
    /// A received record opened full size.
    @Published var open: SavedRecord?
}

final class LibraryWindowController {
    static let shared = LibraryWindowController()
    let nav = LibraryNavigation()
    private var window: NSWindow?
    var model: PlayerModel?

    func show(_ section: LibrarySection? = nil, page: CollectionPage? = nil, record: SavedRecord? = nil) {
        if let section { nav.section = section }
        if let page { nav.section = .collection; nav.collectionPage = page }
        if let record { nav.section = .collection; nav.collectionPage = .received; nav.open = record }
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

    var body: some View {
        NavigationSplitView {
            List(LibrarySection.allCases, selection: $nav.section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch nav.section ?? .collection {
                case .collection:
                    VStack(spacing: 0) {
                        Picker("", selection: $nav.collectionPage) {
                            ForEach(CollectionPage.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pageTabs()
                        switch nav.collectionPage {
                        case .liked: LikedView(model: model)
                        case .playlists: PlaylistsView(model: model)
                        case .crate: CrateDigView(model: model)
                        case .received: ReceivedView(model: model, nav: nav)
                        }
                    }
                case .history:
                    VStack(spacing: 0) {
                        Picker("", selection: $nav.historyPage) {
                            ForEach(HistoryPage.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pageTabs()
                        switch nav.historyPage {
                        case .played: HistoryView(model: model)
                        case .recap: RecapView(model: model)
                        }
                    }
                case .settings: SettingsForm(model: model).frame(maxWidth: 620)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension View {
    /// The page switcher at the top of a library section.
    func pageTabs() -> some View {
        self.pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 14)
            .padding(.bottom, 4)
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

/// The share menu for a song: Copy Link first, then the usual apps, then the Mac's own share menu.
/// The link opens the song as a sealed record on Crate's page.
struct ShareMenu: View {
    let track: Track
    let model: PlayerModel

    var body: some View {
        if let url = ShareLinks.url(for: track, pet: PetSpec.at(model.pet).name) {
            ShareOptions(url: url, title: track.title, message: ShareLinks.message(for: track)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// A menu of ways to send a record link. Every share button in the app uses it.
struct ShareOptions<Content: View>: View {
    let url: URL
    let title: String
    let message: String
    @ViewBuilder var label: () -> Content

    var body: some View {
        Menu {
            Button { ShareActions.copy(url) } label: { Label("Copy Link", systemImage: "link") }
            Divider()
            Button { ShareActions.send(.composeMessage, url: url, message: message) } label: { Label("Messages", systemImage: "message") }
            Button { ShareActions.open("https://wa.me/?text=" + ShareActions.enc(message + " " + url.absoluteString)) } label: { Label("WhatsApp", systemImage: "phone.bubble") }
            Button { ShareActions.open("https://t.me/share/url?url=" + ShareActions.enc(url.absoluteString) + "&text=" + ShareActions.enc(message)) } label: { Label("Telegram", systemImage: "paperplane") }
            Button { ShareActions.send(.composeEmail, url: url, message: message, subject: title) } label: { Label("Mail", systemImage: "envelope") }
            Button { ShareActions.send(.sendViaAirDrop, url: url, message: message) } label: { Label("AirDrop", systemImage: "dot.radiowaves.left.and.right") }
            Divider()
            ShareLink(item: url, subject: Text(title), message: Text(message)) { Label("More…", systemImage: "square.and.arrow.up") }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Share as a record")
    }
}

enum ShareActions {
    static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    static func open(_ link: String) {
        if let u = URL(string: link) { NSWorkspace.shared.open(u) }
    }

    /// Messages, Mail and AirDrop through the Mac's own sharing services.
    static func send(_ name: NSSharingService.Name, url: URL, message: String, subject: String? = nil) {
        guard let service = NSSharingService(named: name) else { copy(url); return }
        if let subject { service.subject = subject }
        let items: [Any] = name == .sendViaAirDrop ? [url] : [message, url]
        if service.canPerform(withItems: items) { service.perform(withItems: items) } else { copy(url) }
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

// MARK: - Received

/// Records people sent you as links and you opened on this Mac.
private struct ReceivedView: View {
    let model: PlayerModel
    @ObservedObject var nav: LibraryNavigation
    @ObservedObject private var links = LinkInbox.shared

    var body: some View {
        if let open = nav.open {
            VStack(spacing: 0) {
                HStack {
                    Button { nav.open = nil } label: { Label("Received", systemImage: "chevron.left") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(12)
                SharedRecordView(record: open.record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(hex: "#121013"))
        } else if links.records.isEmpty {
            ContentUnavailableView("No records yet", systemImage: "opticaldisc",
                                   description: Text("When someone sends you a record link and you open it on this Mac, it's kept here."))
        } else {
            List(links.records) { r in
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
                .onTapGesture { nav.open = r }
                .contextMenu {
                    Button("Play on My Turntable") { Spotify.play(id: r.record.spotifyID, title: r.record.title, artist: r.record.artist) }
                    Button("Delete", role: .destructive) { links.remove(r) }
                }
            }
        }
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
                    SongRow(entry: e, detail: relative(e.playedAt), model: model)
                        .contextMenu { Button("Remove from History", role: .destructive) { history.remove(e) } }
                }
            } else {
                List(history.topSongs) { item in
                    SongRow(entry: item.entry, detail: "\(item.plays) play" + (item.plays == 1 ? "" : "s"), model: model)
                }
            }
        }
    }
}

// MARK: - Welcome

final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    func show(model: PlayerModel) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
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
    @State private var chosenPet = 0

    var body: some View {
        VStack(spacing: 22) {
            if step == 0 {
                Image(systemName: "record.circle").font(.system(size: 48)).foregroundStyle(Tokens.accent.color)
                Text("Where should your turntable live?").font(.title.bold())
                HStack(spacing: 10) {
                    ForEach(DisplayMode.allCases) { m in
                        VStack(spacing: 10) {
                            Image(systemName: m.symbol).font(.system(size: 34))
                            Text(m.rawValue).font(.headline)
                            Text(m.blurb).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .frame(width: 200, height: 170)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(prefs.displayMode == m ? 0.1 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(prefs.displayMode == m ? Tokens.accent.color : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                        .onTapGesture { prefs.displayMode = m }
                    }
                }
                Text("Change this anytime in Settings: right-click the turntable, click ⚙ in the notch, or open Vinyl Player again from Applications.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
                Button("Next") { chosenPet = model.pet; withAnimation(.easeInOut(duration: 0.25)) { step = 1 } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                PetSprite(pet: chosenPet, pose: PetPose(arms: .up, eyes: .happy), pixel: 4)
                Text("Start with a pet?").font(.title.bold())
                Text("A little pixel pet lives next to your record. It dances while the music plays and works the tonearm. You can turn it off anytime in Settings or by right-clicking the turntable.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 5), spacing: 10) {
                    ForEach(Array(PetSpec.all.enumerated()), id: \.offset) { i, p in
                        VStack(spacing: 4) {
                            PetSprite(pet: i, pose: PetPose(), pixel: 2)
                                .frame(height: 38, alignment: .bottom)
                            Text(p.name).font(.caption)
                        }
                        .frame(width: 64, height: 66)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(chosenPet == i ? 0.1 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chosenPet == i ? Tokens.accent.color : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                        .onTapGesture { chosenPet = i }
                        .accessibilityLabel(p.name)
                        .accessibilityAddTraits(chosenPet == i ? .isSelected : [])
                    }
                }
                HStack(spacing: 12) {
                    Button("Back") { withAnimation(.easeInOut(duration: 0.25)) { step = 0 } }
                    Spacer()
                    Button("Start without a pet") { finish(pet: false) }
                    Button("Start with " + PetSpec.at(chosenPet).name) { finish(pet: true) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: 480)
            }
        }
        .padding(32)
        .frame(width: 640, height: 560)
    }

    private func finish(pet: Bool) {
        prefs.showPet = pet
        if pet { model.selectPet(chosenPet) }
        prefs.didOnboard = true
        done()
    }
}
