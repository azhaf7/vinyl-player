import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// Album art and its tint. Order of priority: the user's own cover, then the playback source's artwork URL,
/// then the iTunes Search API. Files live in the shared container so the widgets can show them.
final class ArtworkService: ObservableObject {
    static let shared = ArtworkService()

    @Published private(set) var revision = 0

    private struct Entry: Codable {
        var file: String?
        var tint: String?
        var album: String?
        var url: String?
        var customFile: String?
        var customTint: String?
    }

    private var index: [String: Entry] = [:]
    private var images: [String: NSImage] = [:]
    private var pending: Set<String> = []
    private let indexURL = SharedStore.coversURL.appendingPathComponent("index.json")

    private init() {
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            index = saved
        }
    }

    // MARK: Reading

    func image(for track: Track) -> NSImage? {
        let sourceURL = track.artworkURL.flatMap(URL.init(string:))
        let key = track.key
        if let img = images[key] { return img }
        if let file = coverFile(for: track), let img = NSImage(contentsOf: SharedStore.coversURL.appendingPathComponent(file)) {
            images[key] = img
            return img
        }
        lookup(track, sourceURL: sourceURL)
        return nil
    }

    func tint(for track: Track) -> RGB {
        let e = index[track.key]
        if let hex = e?.customTint ?? (e?.customFile == nil ? e?.tint : nil) { return RGB(hex: hex) }
        return track.fallbackTint
    }

    /// File name (inside `SharedStore.coversURL`) of the cover to show, if one is on disk.
    func coverFile(for track: Track) -> String? {
        let e = index[track.key]
        return e?.customFile ?? e?.file
    }

    /// A public web address for the cover (for share links): the music app's own, or the iTunes one.
    func remoteURL(for track: Track) -> String? {
        let candidate = track.artworkURL ?? index[track.key]?.url
        guard let c = candidate, c.hasPrefix("https://") else { return nil }
        return c
    }

    func hasCustomCover(_ track: Track) -> Bool { index[track.key]?.customFile != nil }

    // MARK: Custom covers

    func pickCustomCover(for track: Track) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a cover for “\(track.title)”"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url),
              let prepared = Self.prepare(img) else { return }
        let jpeg = prepared.0, tint = prepared.1
        let file = Self.fileName(track.key) + "-custom.jpg"
        try? jpeg.write(to: SharedStore.coversURL.appendingPathComponent(file))
        var e = index[track.key] ?? Entry()
        e.customFile = file; e.customTint = tint.hex
        index[track.key] = e
        images[track.key] = nil
        save()
    }

    func clearCustomCover(for track: Track) {
        guard var e = index[track.key], let file = e.customFile else { return }
        try? FileManager.default.removeItem(at: SharedStore.coversURL.appendingPathComponent(file))
        e.customFile = nil; e.customTint = nil
        index[track.key] = e
        images[track.key] = nil
        save()
    }

    // MARK: Lookup

    private func lookup(_ track: Track, sourceURL: URL?) {
        let key = track.key
        guard index[key]?.file == nil, !pending.contains(key) else { return }
        pending.insert(key)
        if let sourceURL {
            download(sourceURL, key: key, album: nil)
            return
        }
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [URLQueryItem(name: "media", value: "music"), URLQueryItem(name: "entity", value: "song"),
                            URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "term", value: track.title + " " + track.artist)]
        URLSession.shared.dataTask(with: comps.url!) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let best = Self.pick(results, for: track),
                  let art = best["artworkUrl100"] as? String else {
                DispatchQueue.main.async { self.pending.remove(key) }
                return
            }
            let big = art.replacingOccurrences(of: #"/\d+x\d+bb\."#, with: "/600x600bb.", options: .regularExpression)
            guard let url = URL(string: big) else { DispatchQueue.main.async { self.pending.remove(key) }; return }
            self.download(url, key: key, album: best["collectionName"] as? String)
        }.resume()
    }

    private func download(_ url: URL, key: String, album: String?) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            let prepared = data.flatMap { NSImage(data: $0) }.flatMap { Self.prepare($0) }
            DispatchQueue.main.async {
                self.pending.remove(key)
                guard let prepared else { return }
                let jpeg = prepared.0, tint = prepared.1
                let file = Self.fileName(key) + ".jpg"
                try? jpeg.write(to: SharedStore.coversURL.appendingPathComponent(file))
                var e = self.index[key] ?? Entry()
                e.file = file; e.tint = tint.hex; e.album = album; e.url = url.absoluteString
                self.index[key] = e
                self.images[key] = nil
                self.save()
            }
        }.resume()
    }

    /// Same scoring as the prototype's vinyl-shared.js → lookup().
    static func pick(_ results: [[String: Any]], for track: Track) -> [String: Any]? {
        func norm(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+-\s+.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        func matches(_ s: String, _ pattern: String) -> Bool {
            s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let bad = "remix|live|karaoke|instrumental|acoustic|sped up|slowed|cover|tribute|8-bit|lullaby"
        let want = norm(track.title), artist = track.artist.lowercased()
        var best: [String: Any]?, bestScore = Int.min
        for x in results {
            let name = x["trackName"] as? String ?? "", album = x["collectionName"] as? String ?? ""
            guard norm(name) == want, !matches(name, bad), !matches(album, bad) else { continue }
            let an = (x["artistName"] as? String ?? "").lowercased()
            var s = 10
            if an == artist { s += 6 } else if an.contains(artist) { s += 3 } else { continue }
            if !matches(album, #" - (single|ep)$"#) { s += 4 }
            if matches(album, "deluxe|remaster|anniversary|expanded") { s -= 1 }
            if matches(album, "greatest|hits|best of|collection|essentials|now that") { s -= 3 }
            if s > bestScore { best = x; bestScore = s }
        }
        return best
    }

    // MARK: Image processing

    /// Square-crops to 600 px JPEG and measures the dominant tint:
    /// weight = saturation² × (1 − |luminance − 0.5|) + 0.02, sampled on a 300×300 downscale.
    static func prepare(_ img: NSImage) -> (Data, RGB)? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = min(cg.width, cg.height)
        guard let square = cg.cropping(to: CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)) else { return nil }
        guard let big = draw(square, size: 600), let small = draw(square, size: 300) else { return nil }
        let rep = NSBitmapImageRep(cgImage: big)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else { return nil }
        return (jpeg, tint(of: small))
    }

    private static func draw(_ img: CGImage, size: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    private static func tint(of img: CGImage) -> RGB {
        guard let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return Tokens.fallbackTint }
        let count = CFDataGetLength(data)
        var r = 0.0, g = 0.0, b = 0.0, w = 0.0
        var i = 0
        while i + 2 < count {
            let R = Double(p[i]), G = Double(p[i + 1]), B = Double(p[i + 2])
            let mx = max(R, G, B), mn = min(R, G, B)
            let sat = mx > 0 ? (mx - mn) / mx : 0, lum = (mx + mn) / 510
            let wt = sat * sat * (1 - abs(lum - 0.5)) + 0.02
            r += R * wt; g += G * wt; b += B * wt; w += wt
            i += 16
        }
        guard w > 0 else { return Tokens.fallbackTint }
        return RGB(r / w / 255, g / w / 255, b / w / 255)
    }

    private static func fileName(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexURL) }
        revision += 1
    }
}
