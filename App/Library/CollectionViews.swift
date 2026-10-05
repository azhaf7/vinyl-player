import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Song row

/// A song with play, like, send and "add to playlist".
struct SongRow: View {
    let entry: HistoryEntry
    let detail: String
    let model: PlayerModel
    var onPlay: (() -> Void)? = nil
    @ObservedObject private var collection = CollectionStore.shared

    var body: some View {
        HStack(spacing: 12) {
            TrackArt(track: entry.track, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.headline)
                Text(entry.artist + (entry.album.map { " · " + $0 } ?? "")).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Button {
                if let onPlay { onPlay() } else { Spotify.play(id: entry.spotifyID, title: entry.title, artist: entry.artist) }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Play")
            LikeButton(track: entry.track)
            AddToPlaylistMenu(entry: entry)
            SendMenu(track: entry.track, model: model)
        }
        .padding(.vertical, 3)
    }
}

struct LikeButton: View {
    let track: Track
    var size: CGFloat = 13
    var tint: Color = .pink
    @ObservedObject private var collection = CollectionStore.shared

    var body: some View {
        let liked = collection.isLiked(track)
        Button { collection.toggleLike(track) } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(liked ? tint : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help(liked ? "Unlike" : "Like")
    }
}

struct AddToPlaylistMenu: View {
    let entry: HistoryEntry
    @ObservedObject private var collection = CollectionStore.shared

    var body: some View {
        Menu {
            ForEach(collection.playlists) { p in
                Button(p.name) { collection.add(entry, to: p) }
            }
            if !collection.playlists.isEmpty { Divider() }
            Button("New Playlist with This Song") {
                let p = collection.createPlaylist("Playlist \(collection.playlists.count + 1)")
                collection.add(entry, to: p)
            }
        } label: {
            Image(systemName: "text.badge.plus")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Add to a playlist")
    }
}

private func relativeDate(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

// MARK: - Liked

struct LikedView: View {
    let model: PlayerModel
    @ObservedObject private var collection = CollectionStore.shared

    var body: some View {
        if collection.liked.isEmpty {
            ContentUnavailableView("No liked songs yet", systemImage: "heart",
                                   description: Text("Tap ♥ on the turntable, in the notch or anywhere in the Library. Shortcut: ⌃⌥L."))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(collection.liked.count) liked songs").foregroundStyle(.secondary)
                    Spacer()
                    Button("Make a Playlist from Liked Songs") {
                        let p = collection.createPlaylist("Liked Songs")
                        collection.liked.forEach { collection.add($0, to: p) }
                    }
                }
                .padding(16)
                List(collection.liked) { e in
                    SongRow(entry: e, detail: relativeDate(e.playedAt), model: model)
                        .contextMenu { Button("Unlike", role: .destructive) { collection.unlike(e) } }
                }
            }
        }
    }
}

// MARK: - Playlists

struct PlaylistsView: View {
    let model: PlayerModel
    @ObservedObject private var collection = CollectionStore.shared
    @ObservedObject private var player = PlaylistPlayer.shared
    @State private var selected: UUID?
    @State private var name = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(collection.playlists) { p in
                        Label(p.name, systemImage: player.playlist?.id == p.id ? "speaker.wave.2.fill" : "music.note.list")
                            .tag(p.id)
                            .contextMenu { Button("Delete Playlist", role: .destructive) { collection.delete(p) } }
                    }
                }
                Divider()
                Button {
                    selected = collection.createPlaylist("Playlist \(collection.playlists.count + 1)").id
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
            .frame(width: 210)
            Divider()
            if let id = selected, let p = collection.playlist(id) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Name", text: Binding(get: { p.name }, set: { collection.rename(p, to: $0) }))
                            .textFieldStyle(.plain)
                            .font(.title2.bold())
                        Spacer()
                        if player.playlist?.id == p.id {
                            Button("Stop") { player.stop() }
                        }
                        Button {
                            player.play(p)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(p.songs.isEmpty)
                    }
                    Text("\(p.songs.count) songs · plays through Spotify, or the sample songs").font(.caption).foregroundStyle(.secondary)
                    if p.songs.isEmpty {
                        ContentUnavailableView("Empty playlist", systemImage: "music.note.list",
                                               description: Text("Add songs from History or Liked with the playlist button."))
                    } else {
                        List {
                            ForEach(Array(p.songs.enumerated()), id: \.element.id) { i, e in
                                SongRow(entry: e, detail: player.playlist?.id == p.id && player.position == i ? "Now playing" : "\(i + 1)",
                                        model: model, onPlay: { player.play(p, from: i) })
                                    .contextMenu { Button("Remove from Playlist", role: .destructive) { collection.remove(e, from: p) } }
                            }
                            .onMove { collection.move(in: p, from: $0, to: $1) }
                        }
                    }
                }
                .padding(20)
            } else {
                ContentUnavailableView("Your playlists", systemImage: "music.note.list",
                                       description: Text("Make a playlist, then add songs from History or Liked."))
            }
        }
        .onAppear { if selected == nil { selected = collection.playlists.first?.id } }
    }
}

// MARK: - Crate digging

/// Flip through records like a crate at a record shop.
struct CrateDigView: View {
    let model: PlayerModel
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var collection = CollectionStore.shared
    @State private var source = "history"
    @State private var current: UUID?

    private var entries: [HistoryEntry] {
        switch source {
        case "liked": return collection.liked
        case "history":
            var seen = Set<String>()
            return history.entries.filter { seen.insert(CollectionStore.key($0.title, $0.artist)).inserted }
        default:
            return collection.playlists.first { $0.id.uuidString == source }?.songs ?? []
        }
    }

    var body: some View {
        let list = entries
        VStack(spacing: 18) {
            Picker("Crate", selection: $source) {
                Text("Everything I've played").tag("history")
                Text("Liked").tag("liked")
                ForEach(collection.playlists) { p in Text(p.name).tag(p.id.uuidString) }
            }
            .frame(width: 320)
            .padding(.top, 16)

            if list.isEmpty {
                ContentUnavailableView("This crate is empty", systemImage: "square.stack", description: Text("Play, like or add songs to fill it."))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: -40) {
                        ForEach(list) { e in
                            TrackArt(track: e.track, size: 220, radius: 6)
                                .drawingGroup()
                                .shadow(color: .black.opacity(0.45), radius: 12, x: 6, y: 10)
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .rotation3DEffect(.degrees(phase.value * -55), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                                        .scaleEffect(1 - abs(phase.value) * 0.18)
                                        .opacity(1 - abs(phase.value) * 0.35)
                                }
                                .id(e.id)
                                .onTapGesture { withAnimation(.spring(response: 0.4)) { current = e.id } }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 300)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $current, anchor: .center)
                .frame(height: 280)
                .overlay(alignment: .leading) {
                    StepButton(symbol: "chevron.left", enabled: position(in: list) > 0) { step(-1, in: list) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .padding(.leading, 16)
                }
                .overlay(alignment: .trailing) {
                    StepButton(symbol: "chevron.right", enabled: position(in: list) < list.count - 1) { step(1, in: list) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .padding(.trailing, 16)
                }

                if let e = list.first(where: { $0.id == current }) ?? list.first {
                    VStack(spacing: 6) {
                        Text(e.title).font(.title2.bold())
                        Text(e.artist + (e.album.map { " · " + $0 } ?? "")).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            Button { Spotify.play(id: e.spotifyID, title: e.title, artist: e.artist) } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            LikeButton(track: e.track, size: 16)
                            AddToPlaylistMenu(entry: e)
                            SendMenu(track: e.track, model: model)
                        }
                        .padding(.top, 6)
                    }
                }
                Text("Click ‹ ›, press the arrow keys or swipe to flip through the crate.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onChange(of: source) { current = nil }
    }

    private func position(in list: [HistoryEntry]) -> Int {
        list.firstIndex { $0.id == current } ?? 0
    }

    /// One record along, with a soft spring so the crate glides rather than jumps.
    private func step(_ dir: Int, in list: [HistoryEntry]) {
        guard !list.isEmpty else { return }
        let j = max(0, min(list.count - 1, position(in: list) + dir))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { current = list[j].id }
    }
}

/// Round ‹ › button for flipping through a row of records.
struct StepButton: View {
    let symbol: String
    var enabled = true
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .frame(width: size, height: size)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .help(symbol == "chevron.left" ? "Previous record" : "Next record")
    }
}

// MARK: - Weekly recap

struct RecapStats {
    let plays: Int
    let minutes: Int
    let days: Int
    let top: [(entry: HistoryEntry, plays: Int)]
    let topArtist: String?

    init(_ entries: [HistoryEntry]) {
        plays = entries.count
        minutes = Int(entries.reduce(0) { $0 + ($1.duration ?? 210) } / 60)
        days = Set(entries.map { Calendar.current.startOfDay(for: $0.playedAt) }).count
        var counts: [String: (HistoryEntry, Int)] = [:]
        var artists: [String: Int] = [:]
        for e in entries {
            let k = CollectionStore.key(e.title, e.artist)
            counts[k] = (counts[k]?.0 ?? e, (counts[k]?.1 ?? 0) + 1)
            artists[e.artist, default: 0] += 1
        }
        top = counts.values.sorted { $0.1 > $1.1 }.prefix(5).map { (entry: $0.0, plays: $0.1) }
        topArtist = artists.max { $0.value < $1.value }?.key
    }
}

/// The shareable card: drawn the same in the app and in the exported image.
struct RecapCard: View {
    let stats: RecapStats
    let pet: Int
    let petTint: RGB?
    let accent: RGB

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MY WEEK ON VINYL").font(.system(size: 12, weight: .bold)).tracking(1.5).foregroundStyle(accent.color)
                    Text("\(stats.minutes) minutes").font(.system(size: 34, weight: .heavy)).foregroundStyle(.white)
                    Text("\(stats.plays) songs · \(stats.days) day\(stats.days == 1 ? "" : "s") of listening")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                PetSprite(pet: pet, pose: PetPose(arms: .up, eyes: .happy), pixel: 4, tint: petTint)
            }
            if let artist = stats.topArtist {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOP ARTIST").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.5))
                    Text(artist).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("TOP SONGS").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.5))
                ForEach(Array(stats.top.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(accent.color).frame(width: 16)
                        MiniRecord(diameter: 40, style: VinylStyle.at(0), art: ArtworkService.shared.image(for: item.entry.track),
                                   artIndex: i, artInset: LP.artInset(for: 40), sheen: false)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.entry.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            Text(item.entry.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        }
                        .lineLimit(1)
                        Spacer()
                        Text("\(item.plays)×").font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            Text("Vinyl Player").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
        }
        .padding(24)
        .frame(width: 380)
        .background(
            LinearGradient(colors: [accent.mix(RGB(hex: "#161214"), 0.35).color, Color(hex: "#121013")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct RecapView: View {
    let model: PlayerModel
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var artwork = ArtworkService.shared
    @State private var note: String?

    var body: some View {
        let _ = artwork.revision
        let stats = RecapStats(history.thisWeek)
        let card = RecapCard(stats: stats, pet: model.pet, petTint: prefs.style.pet, accent: prefs.style.accentColor)
        ScrollView {
            VStack(spacing: 18) {
                if stats.plays == 0 {
                    ContentUnavailableView("Nothing this week yet", systemImage: "calendar",
                                           description: Text("Your recap fills up as you listen."))
                } else {
                    card
                    HStack {
                        Button { copy(card) } label: { Label("Copy Image", systemImage: "doc.on.doc") }
                        Button { save(card) } label: { Label("Save Image…", systemImage: "square.and.arrow.down") }
                        if let image = render(card) {
                            ShareLink(item: Image(nsImage: image), preview: SharePreview("My week on vinyl", image: Image(nsImage: image))) {
                                Label("Share…", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func render(_ card: RecapCard) -> NSImage? {
        let r = ImageRenderer(content: card)
        r.scale = 2
        return r.nsImage
    }

    private func copy(_ card: RecapCard) {
        guard let img = render(card) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        note = "Copied. Paste it into Messages or anywhere."
    }

    private func save(_ card: RecapCard) {
        guard let img = render(card), let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "My week on vinyl.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
            note = "Saved."
        }
    }
}
